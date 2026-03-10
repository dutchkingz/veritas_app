class ArticlesController < ApplicationController
  def show
    @article = Article.includes(:country, :region, :ai_analysis, :narrative_arcs).find(params[:id])

    return unless @article.content.blank? && @article.source_url.present?

    begin
      require 'open-uri'
      require 'readability'

      # We spoof comprehensive browser headers to bypass simple bot protections
      html = URI.open(@article.source_url,
                      "User-Agent" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
                      "Accept" => "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
                      "Accept-Language" => "en-US,en;q=0.5",
                      "Referer" => "https://www.google.com/").read

      doc = Readability::Document.new(html,
                                      tags: %w[div p h1 h2 h3 h4 h5 h6 ul ol li b i strong em blockquote],
                                      attributes: %w[href],
                                      remove_empty_nodes: true)

      @article.update!(content: doc.content)
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
end
