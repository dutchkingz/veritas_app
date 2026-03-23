class FetchArticlesJob < ApplicationJob
  queue_as :default

  INTERVAL = 30.minutes

  def perform
    return skip_and_reschedule("DEMO mode active") if VeritasMode.demo?
    return skip_and_reschedule("API limit reached") if VeritasMode.api_limit_reached?

    service       = NewsApiService.new
    articles_data = service.fetch_latest

    if articles_data.empty?
      Rails.logger.info "[FetchArticlesJob] No new articles to import."
      reschedule
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

    Rails.logger.info "[FetchArticlesJob] Imported #{created} new articles, queued AI analysis + embedding generation."
    reschedule
  end

  private

  def reschedule
    self.class.set(wait: INTERVAL).perform_later
    Rails.logger.info "[FetchArticlesJob] Next fetch in #{INTERVAL / 60} minutes."
  end

  def skip_and_reschedule(reason)
    Rails.logger.info "[FetchArticlesJob] Skipped: #{reason}. Retrying in #{INTERVAL / 60} minutes."
    reschedule
  end
end
