require "net/http"
require "json"

class NewsApiService
  BASE_URL      = "https://newsapi.org/v2/everything".freeze
  HEADLINES_URL = "https://newsapi.org/v2/top-headlines".freeze

  # Rich geopolitical query for the recurring fetch job.
  # NewsAPI free tier supports boolean operators on the `everything` endpoint.
  GEOPOLITICAL_QUERY = (
    "geopolitics OR sanctions OR military OR diplomatic OR nuclear " \
    "OR conflict OR treaty OR NATO OR \"United Nations\" OR sovereignty " \
    "OR espionage OR propaganda OR disinformation OR \"foreign policy\" " \
    "OR embargo OR alliance OR \"trade war\" OR \"cyber attack\" " \
    "OR referendum OR coup OR ukraine OR taiwan OR iran"
  ).freeze

  DEFAULT_DEMO_QUERIES = [
    "geopolitics",
    "ukraine OR russia",
    "china OR taiwan",
    "\"middle east\" OR iran OR israel",
    "\"trade war\" OR sanctions",
    "\"cyber attack\" OR disinformation"
  ].freeze

  # Daily call budget — free tier is 100/day; we reserve 10 for user searches.
  DAILY_FETCH_LIMIT = 90

  def initialize
    @api_key = ENV["NEWS_API_KEY"]
  end

  # Returns an array of attribute hashes ready for Article.create!
  # Skips articles already present in the DB (dedup by source_url).
  # Used by FetchArticlesJob (recurring, every 30 min).
  def fetch_latest(query: GEOPOLITICAL_QUERY, page_size: 20, page: 1)
    return log_skip("demo mode") if VeritasMode.demo?
    return log_skip("API key not configured") if @api_key.blank?
    return log_skip("daily API limit reached (#{calls_today}/#{DAILY_FETCH_LIMIT})") if api_limit_reached?

    raw = call_api(BASE_URL, query: query, page_size: page_size, page: page)
    track_api_call!
    return [] if raw.empty?

    existing_urls = Article.where(source_url: raw.map { |a| a["url"] }).pluck(:source_url).to_set

    raw.filter_map do |item|
      next if item["url"].blank? || existing_urls.include?(item["url"])
      build_article_attrs(item)
    end
  rescue => e
    Rails.logger.error "[NewsApiService] fetch_latest failed: #{e.class}: #{e.message}"
    []
  end

  # Fetches top geopolitical headlines — supplementary to fetch_latest.
  # Used as a second pass when fresh article count is low.
  def fetch_top_headlines(country: nil, page_size: 20)
    return [] if VeritasMode.demo?
    return [] if @api_key.blank?
    return [] if api_limit_reached?

    params = { category: "general", pageSize: page_size, apiKey: @api_key, language: "en" }
    params[:country] = country if country.present?

    uri       = URI(HEADLINES_URL)
    uri.query = URI.encode_www_form(params)
    response  = Net::HTTP.get(uri)
    data      = JSON.parse(response)
    track_api_call!

    return [] unless data["status"] == "ok"

    existing_urls = Article.pluck(:source_url).to_set

    (data["articles"] || []).filter_map do |item|
      next if item["url"].blank? || existing_urls.include?(item["url"])
      build_article_attrs(item)
    end
  rescue => e
    Rails.logger.error "[NewsApiService] fetch_top_headlines failed: #{e.class}: #{e.message}"
    []
  end

  def fetch_demo_batch(limit: 200, queries: DEFAULT_DEMO_QUERIES, page_size: 100, max_pages_per_query: 3)
    return [] if @api_key.blank?

    existing_urls = Article.pluck(:source_url).to_set
    collected     = []

    queries.each do |query|
      break if collected.size >= limit

      (1..max_pages_per_query).each do |page|
        break if collected.size >= limit

        raw = call_api(BASE_URL, query: query, page_size: page_size, page: page)
        break if raw.empty?

        new_items = raw.filter_map do |item|
          url = item["url"]
          next if url.blank? || existing_urls.include?(url)

          existing_urls << url
          build_article_attrs(item)
        end

        collected.concat(new_items)
        break if new_items.empty?
      end
    end

    collected.first(limit)
  rescue => e
    Rails.logger.error "[NewsApiService] demo batch failed: #{e.class} #{e.message}"
    []
  end

  # Fetches articles for an arbitrary user-supplied query string.
  # Used by FreshIntelligenceJob during live search.
  # Results are cached per query per day — 50 users searching "Trump" = 1 API call.
  def fetch_by_query(query_string, max_results: 20)
    return [] if VeritasMode.demo?
    return [] if @api_key.blank?
    return [] if api_limit_reached?

    cache_key = "newsapi:search:#{query_string.parameterize}:#{Date.current}"

    raw = Rails.cache.fetch(cache_key, expires_in: 6.hours) do
      result = call_api(BASE_URL, query: query_string, page_size: [max_results, 100].min, page: 1)
      track_api_call! if result.any?
      result
    end

    return [] if raw.empty?

    existing_urls = Article.where(source_url: raw.map { |a| a["url"] }).pluck(:source_url).to_set

    raw.filter_map do |item|
      next if item["url"].blank? || existing_urls.include?(item["url"])
      build_article_attrs(item)
    end
  rescue => e
    Rails.logger.error "[NewsApiService] fetch_by_query failed: #{e.class} #{e.message}"
    []
  end

  def calls_today
    Rails.cache.read("newsapi_calls:#{Date.today}").to_i
  end

  def calls_remaining
    DAILY_FETCH_LIMIT - calls_today
  end

  private

  def build_article_attrs(item)
    geo = GeolocatorService.call(item)

    {
      headline:       item["title"],
      source_url:     item["url"],
      source_name:    item.dig("source", "name") || "Unknown",
      published_at:   item["publishedAt"],
      fetched_at:     Time.current,
      latitude:       geo[:latitude],
      longitude:      geo[:longitude],
      country:        geo[:country],
      region:         geo[:region],
      target_country: geo[:target_country_id],
      geo_method:     geo[:geo_method],
      raw_data:       item
    }
  end

  def api_limit_reached?
    calls_today >= DAILY_FETCH_LIMIT
  end

  def track_api_call!
    Rails.cache.increment("newsapi_calls:#{Date.today}", 1, expires_in: 24.hours)
    remaining = calls_remaining
    Rails.logger.info "[NewsApiService] API call tracked. #{remaining} calls remaining today."
    if remaining <= 15
      Rails.logger.warn "[NewsApiService] ⚠️  Only #{remaining} NewsAPI calls remaining today!"
    end
  end

  def log_skip(reason)
    Rails.logger.info "[NewsApiService] Skipping fetch — #{reason}."
    []
  end

  def call_api(base_url, query:, page_size:, page: 1)
    uri       = URI(base_url)
    uri.query = URI.encode_www_form(
      q:        query,
      language: "en",
      pageSize: page_size,
      page:     page,
      sortBy:   "publishedAt",
      apiKey:   @api_key
    )

    response = Net::HTTP.get(uri)
    data     = JSON.parse(response)

    unless data["status"] == "ok"
      code = data["code"]
      msg  = data["message"]
      case code
      when "rateLimited"
        Rails.logger.warn "[NewsApiService] Rate limited by NewsAPI: #{msg}"
      when "apiKeyInvalid", "apiKeyDisabled", "apiKeyExhausted"
        Rails.logger.error "[NewsApiService] API key problem (#{code}): #{msg}"
      when "maximumResultsReached"
        Rails.logger.warn "[NewsApiService] Page limit reached: #{msg}"
      else
        Rails.logger.warn "[NewsApiService] API error (#{code}): #{msg}"
      end
      return []
    end

    data["articles"] || []
  end
end
