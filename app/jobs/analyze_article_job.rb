class AnalyzeArticleJob < ApplicationJob
  queue_as :default

  def perform(article_id)
    article = Article.find(article_id)

    # Skip if already analyzed
    return if %w[complete analyzing].include?(article.ai_analysis&.analysis_status)

    pipeline = AnalysisPipeline.new
    pipeline.analyze(article)
  end
end
