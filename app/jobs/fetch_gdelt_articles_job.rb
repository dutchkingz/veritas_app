class FetchGdeltArticlesJob < ApplicationJob
  queue_as :default

  retry_on GdeltBigQueryService::QueryError, wait: :polynomially_longer, attempts: 3

  # Do NOT retry quota errors — something is wrong, stop immediately
  discard_on GdeltBigQueryService::QuotaExceededError do |_job, error|
    Rails.logger.error "[FetchGdeltArticlesJob] QUOTA EXCEEDED — job discarded: #{error.message}"
  end

  def perform
    if VeritasMode.demo?
      Rails.logger.info "[FetchGdeltArticlesJob] Demo mode — skipping GDELT fetch."
      return
    end

    Rails.logger.info "[FetchGdeltArticlesJob] Starting GDELT fetch..."
    GdeltIngestionService.new.fetch_and_process
  rescue GdeltBigQueryService::QueryError => e
    Rails.logger.error "[FetchGdeltArticlesJob] BigQuery error (will retry): #{e.message}"
    raise
  rescue StandardError => e
    Rails.logger.error "[FetchGdeltArticlesJob] Unexpected error (no retry): #{e.class}: #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
    # Do not re-raise — prevents silent job death from cascading into Solid Queue noise
  end
end
