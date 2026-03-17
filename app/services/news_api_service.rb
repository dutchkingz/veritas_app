require "net/http"
require "json"

class NewsApiService
  BASE_URL = "https://newsapi.org/v2/everything"
  DEFAULT_DEMO_QUERIES = [
    "geopolitics",
    "ukraine OR russia",
    "china OR taiwan",
    "\"middle east\" OR iran OR israel",
    "\"trade war\" OR sanctions",
    "\"cyber attack\" OR disinformation"
  ].freeze

  def initialize
    @api_key = ENV["NEWS_API_KEY"]
  end

  # Returns an array of attribute hashes ready for Article.create!
  # Skips articles already present in the DB (dedup by source_url).
  def fetch_latest(query: "geopolitics", page_size: 20, page: 1)
    return [] if @api_key.blank?

    raw = call_api(query: query, page_size: page_size, page: page)
    return [] if raw.empty?

    existing_urls = Article.where(source_url: raw.map { |a| a["url"] }).pluck(:source_url).to_set

    raw.filter_map do |item|
      next if item["url"].blank? || existing_urls.include?(item["url"])
      build_article_attrs(item)
    end
  rescue => e
    Rails.logger.error "[NewsApiService] #{e.class}: #{e.message}"
    []
  end

  def fetch_demo_batch(limit: 200, queries: DEFAULT_DEMO_QUERIES, page_size: 100, max_pages_per_query: 3)
    return [] if @api_key.blank?

    existing_urls = Article.pluck(:source_url).to_set
    collected = []

    queries.each do |query|
      break if collected.size >= limit

      (1..max_pages_per_query).each do |page|
        break if collected.size >= limit

        raw = call_api(query: query, page_size: page_size, page: page)
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
  def fetch_by_query(query_string, max_results: 20)
    return [] if @api_key.blank?
    return [] if api_limit_reached?

    raw = call_api(query: query_string, page_size: [max_results, 100].min, page: 1)
    track_api_call!
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
    calls_today >= 90
  end

  def calls_today
    Rails.cache.read("newsapi_calls:#{Date.today}").to_i
  end

  def track_api_call!
    Rails.cache.increment("newsapi_calls:#{Date.today}", 1, expires_in: 24.hours)
  end

  def call_api(query:, page_size:, page: 1)
    uri       = URI(BASE_URL)
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
      Rails.logger.warn "[NewsApiService] API error: #{data['message']}"
      return []
    end

    data["articles"] || []
  end
end
