class ArticlesController < ApplicationController
  require 'open-uri'
  require 'readability'
  require 'nokogiri'

  def show
    @article = Article.includes(:country, :region, :ai_analysis, :narrative_arcs).find(params[:id])

    # Find Related Intel via Semantic Similarity (Narrative Convergence)
    # Use .preload (not .includes) + .to_a to avoid pgvector's AS neighbor_distance alias conflict
    @related_articles = if @article.embedding.present?
                          @article.nearest_neighbors(:embedding)
                                  .distance(:cosine)
                                  .preload(:ai_analysis)
                                  .limit(3)
                                  .to_a
                        else
                          []
                        end

    # Kick off the VERITAS Triad analysis pipeline if not yet analyzed
    if @article.ai_analysis.blank? || @article.ai_analysis.analysis_status.nil?
      AnalyzeArticleJob.perform_later(@article.id)
    end

    # Contradiction Engine — semantically similar articles with opposing bias/sentiment
    @contradictions = find_contradictions(@article)

    return unless @article.content.blank? && @article.source_url.present?



    base_uri = URI.parse(@article.source_url)
    base = "#{base_uri.scheme}://#{base_uri.host}"

    begin
      # We spoof comprehensive browser headers to bypass simple bot protections
      html = URI.open(@article.source_url,
                      "User-Agent" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
                      "Accept" => "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
                      "Accept-Language" => "en-US,en;q=0.5",
                      "Referer" => "https://www.google.com/").read

      # PRE-PROCESS: Resolve lazy-loaded images BEFORE Readability processes the HTML.
      # Modern news sites don't put the real URL in `src` — they hide it in `data-src`,
      # `data-lazy-src`, `data-original`, etc. We need to move those into `src` first.
      pre_doc = Nokogiri::HTML(html)
      pre_doc.css('img').each do |img|
        lazy_src = img['data-src'] || img['data-lazy-src'] || img['data-original'] || img['data-srcset']&.split(',')&.first&.strip&.split(' ')&.first
        if lazy_src.present? && (img['src'].blank? || img['src'].include?('data:image') || img['src'].include?('placeholder') || img['src'].include?('1x1'))
          img['src'] = lazy_src
        end
      end
      html = pre_doc.to_html

      doc = Readability::Document.new(html,
                                      tags: %w[div p h1 h2 h3 h4 h5 h6 ul ol li b i strong em blockquote img figure
                                               figcaption picture source span],
                                      attributes: %w[href src srcset alt title class],
                                      remove_empty_nodes: true)

      # POST-PROCESS: Fix relative image URLs → absolute so browsers can load them
      parsed = Nokogiri::HTML(doc.content)
      parsed.css('img').each do |img|
        next if img['src'].blank?

        # Convert relative URLs to absolute
        unless img['src'].start_with?('http')
          img['src'] = img['src'].start_with?('/') ? "#{base}#{img['src']}" : "#{base}/#{img['src']}"
        end
        # Remove srcset to avoid confusion
        img.remove_attribute('srcset')
        # Remove tiny tracking pixels (1x1, 2x2 etc.)
        img.remove if img['src'].include?('1x1') || img['src'].include?('pixel') || img['src'].include?('tracking')
      end

      @article.update!(content: parsed.at('body')&.inner_html || doc.content)
    rescue OpenURI::HTTPError => e
      if e.message.include?('403') || e.message.include?('503') || e.message.include?('429')
        fallback_text = @article.raw_data['description'] || @article.raw_data['content'] || 'Content protected.'

        fallback_html = <<-HTML
            <div style="background: rgba(239, 68, 68, 0.1); border: 1px solid rgba(239, 68, 68, 0.3); color: #ef4444; padding: 15px; border-radius: 4px; font-family: 'Rajdhani', sans-serif;">
              <i class="fa fa-shield-alt me-2"></i>
              <strong>ANTI-BOT COUNTERMEASURES DETECTED (Cloudflare/Paywall).</strong>#{' '}
              <br>Full scrape blocked (Status: #{e.message}). Falling back to intercepted transmission summary...
            </div>
            <p style="margin-top: 20px; font-size: 1.2rem;">#{fallback_text}</p>
        HTML
        @article.update!(content: fallback_html)
      else
        @article.update!(content: "<p class='text-danger'>[SYSTEM WARNING] HTTP Error: #{e.message}. Access Original Source manually.</p>")
      end
    rescue StandardError => e
      @article.update!(content: "<p class='text-danger'>[SYSTEM WARNING] Could not parse document stream: #{e.message}. Access Original Source manually.</p>")
    end
  end

  private

  OPPOSING_BIAS_PAIRS = [
    %w[LEFT RIGHT],
    %w[RIGHT LEFT]
  ].freeze

  def find_contradictions(article)
    return [] unless article.embedding.present? &&
                     article.ai_analysis&.analysis_status == 'complete'

    our_bias      = article.ai_analysis.sentinel_response&.dig('bias_direction')
    our_sentiment = article.ai_analysis.sentiment_label

    candidates = article.nearest_neighbors(:embedding)
                        .distance(:cosine)
                        .joins(:ai_analysis)
                        .where(ai_analyses: { analysis_status: 'complete' })
                        .where.not(id: article.id)
                        .preload(:ai_analysis, :country)
                        .limit(25)
                        .to_a
                        .select { |a| a.neighbor_distance < 0.22 }

    candidates.select { |a|
      their_bias      = a.ai_analysis.sentinel_response&.dig('bias_direction')
      their_sentiment = a.ai_analysis.sentiment_label
      opposing_bias?(our_bias, their_bias) || opposing_sentiments?(our_sentiment, their_sentiment)
    }.first(3)
  end

  def opposing_bias?(a, b)
    return false if a.blank? || b.blank? || a == 'NEUTRAL' || a == 'CENTER' || a == 'UNCLEAR'
    OPPOSING_BIAS_PAIRS.any? { |pair| pair[0] == a && pair[1] == b }
  end

  def opposing_sentiments?(a, b)
    (a == 'POSITIVE' && b == 'NEGATIVE') || (a == 'NEGATIVE' && b == 'POSITIVE')
  end
end
