class AnalyzeArticleJob < ApplicationJob
  queue_as :default

  def perform(article_id)
    article = Article.find(article_id)

    # Skip if already analyzed
    return if %w[complete analyzing].include?(article.ai_analysis&.analysis_status)

    pipeline = AnalysisPipeline.new
    pipeline.analyze(article)

    # AnalysisPipeline generates the embedding (Phase 4).
    # Kick off per-article route generation immediately so new articles appear
    # on the globe within seconds rather than waiting for the hourly batch job.
    article.reload
    if article.embedding.present?
      NarrativeRouteGeneratorService.new.generate_routes_for_article(article)
    end
  rescue StandardError => e
    Rails.logger.error "[AnalyzeArticleJob] Failed for article ##{article_id}: #{e.class} #{e.message}"
    raise
  end
end
