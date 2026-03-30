class FetchArticleContentJob < ApplicationJob
  queue_as :default
  
  # Fetch article content from source URL and save to content field
  def perform(article_id)
    article = Article.find_by(id: article_id)
    return unless article
    return if article.article_images.present?  # Already has images extracted
    
    # Check if we have a valid URL
    source_url = article.source_url.to_s.strip
    if source_url.blank? || !source_url.start_with?('http')
      Rails.logger.warn "[FetchArticleContentJob] Article ##{article_id} has no valid URL"
      return
    end
    
    Rails.logger.info "[FetchArticleContentJob] Fetching content for Article ##{article_id}: #{article.headline}"
    
    begin
      content = fetch_article_content(source_url)
      
      if content.present?
        # Clean up content (remove excessive whitespace, limit size)
        cleaned_content = clean_content(content)

        images = []
        if @last_html.present?
          images = ArticleImageExtractor.new(@last_html, @last_base_url).extract
        end

        article.update!(content: cleaned_content, article_images: images)
        
        Rails.logger.info "[FetchArticleContentJob] ✅ Content saved for Article ##{article_id} (#{cleaned_content.length} chars)"
        
        # Queue AI analysis if not already done.
        # The AnalysisPipeline handles embedding generation in Phase 4 AFTER
        # the TRIAD agents complete — do NOT enqueue GenerateEmbeddingJob here
        # or it will race ahead of the analysis and fail with no summary text.
        if article.ai_analysis.blank?
          AnalyzeArticleJob.perform_later(article.id)
          Rails.logger.info "[FetchArticleContentJob] ✅ AI analysis queued for Article ##{article_id}"
        end
      else
        Rails.logger.warn "[FetchArticleContentJob] ⚠️ No content extracted for Article ##{article_id}"
      end
    rescue => e
      Rails.logger.error "[FetchArticleContentJob] ❌ Error fetching content for Article ##{article_id}: #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")
    end
  end
  
  private
  
  # Fetch content from URL
  def fetch_article_content(url, timeout: 10)
    require 'net/http'
    require 'uri'
    
    uri = URI.parse(url)
    
    # Set up HTTP request
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'
    http.open_timeout = timeout
    http.read_timeout = timeout
    
    request = Net::HTTP::Get.new(uri)
    
    # Set reasonable headers
    request['User-Agent'] = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36'
    request['Accept'] = 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
    request['Accept-Language'] = 'en-US,en;q=0.5'
    
    response = http.request(request)
    
    if response.code == '200'
      # Extract text from HTML (very basic extraction)
      html = response.body
      @last_html     = html
      @last_base_url = url
      extract_text_from_html(html)
    else
      Rails.logger.warn "[FetchArticleContentJob] HTTP #{response.code} for #{url}"
      nil
    end
  rescue => e
    Rails.logger.warn "[FetchArticleContentJob] Network error for #{url}: #{e.message}"
    nil
  end
  
  # Basic HTML to text extraction
  def extract_text_from_html(html)
    # Remove script and style tags
    html = html.gsub(/<script\b[^<]*(?:(?!<\/script>)<[^<]*)*<\/script>/i, '')
    html = html.gsub(/<style\b[^<]*(?:(?!<\/style>)<[^<]*)*<\/style>/i, '')
    
    # Replace common tags with spaces
    html = html.gsub(/<br\s*\/?>/i, "\n")
    html = html.gsub(/<\/p>|<\/div>|<\/h[1-6]>|<\/li>/i, "\n")
    
    # Remove all remaining tags
    text = html.gsub(/<[^>]+>/, ' ')
    
    # Decode HTML entities (basic)
    text = text.gsub(/&nbsp;|&amp;|&lt;|&gt;|&quot;|&#39;/, 
      '&nbsp;' => ' ', '&amp;' => '&', '&lt;' => '<', '&gt;' => '>', '&quot;' => '"', '&#39;' => "'")
    
    # Collapse multiple whitespace
    text = text.gsub(/\s+/, ' ').strip
    
    # Limit length to avoid huge content
    text[0..10000]
  end
  
  def clean_content(content)
    # Remove extra whitespace, normalize newlines
    content = content.to_s.gsub(/\s+/, ' ').strip
    
    # Remove common boilerplate
    boilerplate = [
      'Subscribe to our newsletter',
      'Follow us on',
      'Like us on Facebook',
      'Follow us on Twitter',
      'All rights reserved',
      'Terms of Use',
      'Privacy Policy',
      'Cookie Policy'
    ]
    
    boilerplate.each do |phrase|
      content = content.gsub(/#{Regexp.escape(phrase)}.*$/i, '')
    end
    
    # Limit to reasonable size for embeddings
    content[0..5000]
  end
end