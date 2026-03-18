module Api
  class SearchController < ApplicationController
    skip_before_action :authenticate_user!, only: [:create]

    # POST /api/search
    # Accepts { query: "..." }, returns cached results immediately and enqueues
    # a background job for fresh NewsAPI data if needed.
    def create
      query = params[:query].to_s.strip

      if query.blank? || query.length < 3
        return render json: { error: "Query must be at least 3 characters" },
                      status: :unprocessable_entity
      end

      return render json: { error: "Rate limit exceeded. Try again in 1 minute." },
                    status: :too_many_requests if rate_limited?

      result = IntelligenceSearchService.call(query: query, user: current_user)

      render json: {
        cached_results:  result[:cached_results].map { |a| article_json(a) },
        total_cached:    result[:total_cached],
        fetching_fresh:  result[:fetching_fresh],
        query:           result[:query],
        notice:          result[:notice]
      }
    end

    private

    def rate_limited?
      key     = "search_rate:#{session.id || request.remote_ip}"
      current = Rails.cache.read(key).to_i
      return true if current >= 5

      Rails.cache.write(key, current + 1, expires_in: 1.minute)
      false
    end

    def article_json(article)
      {
        id:              article.id,
        headline:        article.headline,
        source_name:     article.source_name,
        source_url:      article.source_url,
        latitude:        article.latitude,
        longitude:       article.longitude,
        published_at:    article.published_at,
        country:         article.country&.name,
        region:          article.region&.name,
        trust_score:     article.ai_analysis&.trust_score,
        threat_level:    article.ai_analysis&.threat_level,
        sentiment_color: article.ai_analysis&.sentiment_color,
        geo_method:      article.geo_method
      }
    end
  end
end
