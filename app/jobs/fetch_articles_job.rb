class FetchArticlesJob < ApplicationJob
  queue_as :default

  retry_on OpenRouterClient::RateLimitError, wait: :exponentially_longer, attempts: 3

  def perform
    if VeritasMode.demo?
      Rails.logger.info "[FetchArticlesJob] Demo mode — skipping live fetch."
      return
    end

    service = NewsApiService.new

    if service.calls_remaining <= 0
      Rails.logger.warn "[FetchArticlesJob] Daily NewsAPI limit reached — skipping fetch."
      return
    end

    Rails.logger.info "[FetchArticlesJob] Starting geopolitical article fetch (#{service.calls_remaining} API calls remaining)..."

    article_attrs = service.fetch_latest
    Rails.logger.info "[FetchArticlesJob] NewsAPI returned #{article_attrs.size} candidate articles."

    if article_attrs.empty?
      Rails.logger.info "[FetchArticlesJob] No new articles returned."
      return
    end

    filter  = GeopoliticalRelevanceFilter.new
    created = 0
    skipped = 0
    rejected = 0

    article_attrs.each do |attrs|
      headline    = attrs[:headline].to_s
      description = attrs.dig(:raw_data, "description").to_s

      relevance = filter.call(headline: headline, description: description)

      unless relevance[:relevant]
        Rails.logger.info "[FetchArticlesJob] 🚫 Filtered out (#{relevance[:method]}): #{headline.truncate(80)}"
        rejected += 1
        next
      end

      article = Article.create!(attrs)
      AnalyzeArticleJob.perform_later(article.id)
      created += 1
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.warn "[FetchArticlesJob] Skipped (invalid record): #{e.message}"
      skipped += 1
    rescue StandardError => e
      Rails.logger.warn "[FetchArticlesJob] Skipped (unexpected error): #{e.message}"
      skipped += 1
    end

    Rails.logger.info "[FetchArticlesJob] ✅ Done — #{created} saved, #{rejected} filtered, #{skipped} skipped."

    if created > 0
      ActionCable.server.broadcast("globe_channel", {
        type:    "articles_fetched",
        count:   created,
        message: "#{created} new geopolitical articles incoming"
      })
    end
  end
end
