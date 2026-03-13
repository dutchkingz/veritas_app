require "net/http"
require "json"

class NewsApiService
  BASE_URL = "https://newsapi.org/v2/everything"

  def initialize
    @api_key = ENV["NEWS_API_KEY"]
  end

  # Returns an array of attribute hashes ready for Article.create!
  # Skips articles already present in the DB (dedup by source_url).
  def fetch_latest(query: "geopolitics", page_size: 20)
    return [] if @api_key.blank?

    regions = Region.all.to_a
    return [] if regions.empty?

    raw = call_api(query: query, page_size: page_size)
    return [] if raw.empty?

    existing_urls = Article.where(source_url: raw.map { |a| a["url"] }).pluck(:source_url).to_set

    raw.filter_map do |item|
      next if item["url"].blank? || existing_urls.include?(item["url"])

      region  = regions.sample
      country = Country.where(region_id: region.id).first
      next unless country

      {
        headline:       item["title"],
        source_url:     item["url"],
        source_name:    item.dig("source", "name") || "Unknown",
        published_at:   item["publishedAt"],
        fetched_at:     Time.now,
        latitude:       region.latitude  + rand(-2.0..2.0),
        longitude:      region.longitude + rand(-2.0..2.0),
        country:        country,
        region:         region,
        target_country: 1,
        raw_data:       item
      }
    end
  rescue => e
    Rails.logger.error "[NewsApiService] #{e.class}: #{e.message}"
    []
  end

  private

  def call_api(query:, page_size:)
    uri       = URI(BASE_URL)
    uri.query = URI.encode_www_form(
      q:        query,
      language: "en",
      pageSize: page_size,
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
