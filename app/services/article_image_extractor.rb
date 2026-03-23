require 'nokogiri'
require 'uri'

# Extracts editorial images from raw article HTML.
# Filters out ads, tracking pixels, icons, and off-domain CDN junk.
class ArticleImageExtractor
  # Domains associated with ads / tracking — skip any img src containing these
  AD_DOMAINS = %w[
    doubleclick.net googlesyndication.com adnxs.com adsystem.com
    googletagmanager.com googletagservices.com google-analytics.com
    taboola.com outbrain.com chartbeat.com scorecardresearch.com
    adsafeprotected.com moatads.com amazon-adsystem.com
    criteo.com rubiconproject.com openx.net pubmatic.com
    quantserve.com bluekai.com demdex.net
  ].freeze

  # Class/id substrings that suggest an image is an ad or UI chrome
  AD_CLASS_PATTERNS = /\bad[-_]?|sponsor|promo|banner|advertisement|tracking|pixel|beacon|logo|icon|favicon|avatar|author[-_]?photo|social[-_]?|share[-_]?|sharing/i

  # URL fragments that indicate social media icons / share buttons
  SOCIAL_ICON_PATTERNS = %w[
    facebook twitter x.com linkedin pinterest whatsapp telegram
    reddit tumblr instagram youtube tiktok snapchat
    social-icon share-icon sharing btn-
    /social/ /share/ /icons/
  ].freeze

  # Selectors to search for the article body (in priority order)
  CONTENT_SELECTORS = %w[
    article
    [role="main"]
    main
    .article-body
    .article__body
    .story-body
    .story__body
    .post-content
    .entry-content
    .article-content
    .content-body
    #article-body
    #story-body
  ].freeze

  MIN_DIMENSION = 100   # skip images with explicit width or height below this
  MAX_IMAGES    = 12    # cap per article

  def initialize(html, base_url)
    @doc      = Nokogiri::HTML(html)
    @base_url = base_url
  end

  def extract
    container = find_content_container
    return [] unless container

    images    = []
    seen_urls = Set.new

    container.css('img').each do |img|
      src = resolve_src(img)
      next if src.nil?
      next if ad_url?(src)
      next if social_icon?(src, img)
      next if ad_element?(img)
      next if too_small?(img)
      next if seen_urls.include?(src)

      seen_urls << src
      images << { url: src, alt: img['alt'].to_s.strip }
      break if images.size >= MAX_IMAGES
    end

    images
  end

  private

  def find_content_container
    CONTENT_SELECTORS.each do |selector|
      node = @doc.at_css(selector)
      return node if node && node.css('img').any?
    end
    # Fallback: whole body minus nav/header/footer/aside
    body = @doc.at_css('body')
    return nil unless body

    %w[nav header footer aside .sidebar .ad .ads .advertisement].each do |sel|
      body.css(sel).each(&:remove)
    end
    body
  end

  def resolve_src(img)
    # Prefer data-src (lazy-loaded images) over src
    raw = img['data-src'].presence || img['src'].presence
    return nil if raw.blank?
    return nil if raw.start_with?('data:')   # base64 inline — not article content

    begin
      uri = URI.parse(raw)
      if uri.relative?
        base = URI.parse(@base_url)
        uri  = base.merge(uri)
      end
      url = uri.to_s
      # Only http/https
      return nil unless url.start_with?('http://', 'https://')
      url
    rescue URI::InvalidURIError
      nil
    end
  end

  def ad_url?(src)
    AD_DOMAINS.any? { |domain| src.include?(domain) }
  end

  def ad_element?(img)
    [img['class'], img['id'], img.parent['class'], img.parent['id']].compact.any? do |attr|
      attr.match?(AD_CLASS_PATTERNS)
    end
  end

  def social_icon?(src, img)
    src_lower = src.downcase
    return true if SOCIAL_ICON_PATTERNS.any? { |pat| src_lower.include?(pat) }

    alt = img['alt'].to_s.downcase
    return true if alt.match?(/\b(facebook|twitter|linkedin|pinterest|whatsapp|telegram|reddit|instagram|share|email)\b/)

    false
  end

  def too_small?(img)
    w = img['width'].to_i
    h = img['height'].to_i
    (w.positive? && w < MIN_DIMENSION) || (h.positive? && h < MIN_DIMENSION)
  end
end
