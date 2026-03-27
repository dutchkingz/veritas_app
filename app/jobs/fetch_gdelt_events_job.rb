class FetchGdeltEventsJob < ApplicationJob
  queue_as :default

  retry_on GdeltBigQueryService::QueryError, wait: :polynomially_longer, attempts: 3

  # Quota errors mean something is structurally wrong — stop immediately, do not retry
  discard_on GdeltBigQueryService::QuotaExceededError do |_job, error|
    Rails.logger.error "[FetchGdeltEventsJob] QUOTA EXCEEDED — job discarded: #{error.message}"
  end

  def perform
    if VeritasMode.demo?
      Rails.logger.info "[FetchGdeltEventsJob] Demo mode — skipping GDELT Events fetch."
      return
    end

    Rails.logger.info "[FetchGdeltEventsJob] Starting GDELT Events fetch..."
    GdeltEventIngestionService.new.fetch_and_process
  rescue GdeltBigQueryService::QueryError => e
    Rails.logger.error "[FetchGdeltEventsJob] BigQuery error (will retry): #{e.message}"
    raise
  rescue StandardError => e
    Rails.logger.error "[FetchGdeltEventsJob] Unexpected error (no retry): #{e.class}: #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
  end
end
