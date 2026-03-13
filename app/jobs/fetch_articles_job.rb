class FetchArticlesJob < ApplicationJob
  queue_as :default

  def perform
    service       = NewsApiService.new
    articles_data = service.fetch_latest

    if articles_data.empty?
      Rails.logger.info "[FetchArticlesJob] No new articles to import."
      return
    end

    created = 0
    articles_data.each do |attrs|
      article = Article.create!(attrs)
      AnalyzeArticleJob.perform_later(article.id)
      created += 1
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.warn "[FetchArticlesJob] Skipped: #{e.message}"
    end

    Rails.logger.info "[FetchArticlesJob] Imported #{created} new articles, queued AI analysis."
  end
end
