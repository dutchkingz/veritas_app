require "google/cloud/bigquery"

# GdeltBigQueryService
# Low-level BigQuery client wrapper. Nothing GDELT-specific — just query execution.
#
# Usage:
#   service = GdeltBigQueryService.new
#   service.execute_query(sql)                  # estimate cost + execute
#   service.execute_query(sql, dryrun: true)    # estimate cost only, no execution

class GdeltBigQueryService
  class QueryError < StandardError; end

  def initialize
    @project = ENV["GOOGLE_CLOUD_PROJECT"]
    Rails.logger.warn "[GdeltBigQueryService] GOOGLE_CLOUD_PROJECT not set" if @project.blank?

    credentials = ENV["GOOGLE_APPLICATION_CREDENTIALS"]
    Rails.logger.warn "[GdeltBigQueryService] GOOGLE_APPLICATION_CREDENTIALS not set" if credentials.blank?

    @bigquery = Google::Cloud::Bigquery.new(project: @project)
  rescue => e
    raise QueryError, "Failed to initialize BigQuery client: #{e.message}"
  end

  # Executes a BigQuery SQL query.
  # If dryrun: true — estimates bytes and returns MB without executing.
  # If dryrun: false (default) — first estimates, logs cost, then executes and returns rows.
  def execute_query(sql, dryrun: false)
    Rails.logger.info "[GdeltBigQueryService] Query: #{sql.truncate(200)}"

    estimated_mb = estimate_query_cost(sql)
    Rails.logger.info "[GdeltBigQueryService] Estimated cost: #{estimated_mb} MB"

    return estimated_mb if dryrun

    job = @bigquery.query_job(sql)
    job.wait_until_done!

    if job.failed?
      raise QueryError, "BigQuery job failed: #{job.error&.dig('message')}"
    end

    results = job.query_results
    Rails.logger.info "[GdeltBigQueryService] Query returned #{results.count} rows"
    results
  rescue QueryError
    raise
  rescue Google::Cloud::Error => e
    raise QueryError, "BigQuery error: #{e.message}"
  rescue => e
    raise QueryError, "Unexpected BigQuery error: #{e.class}: #{e.message}"
  end

  def estimated_cost_mb(bytes)
    (bytes.to_f / 1.megabyte).round(2)
  end

  private

  def estimate_query_cost(sql)
    job = @bigquery.query_job(sql, dryrun: true)
    bytes = job.statistics&.dig("query", "estimatedBytesProcessed").to_i
    estimated_cost_mb(bytes)
  rescue Google::Cloud::Error => e
    Rails.logger.warn "[GdeltBigQueryService] Dry-run estimate failed: #{e.message}"
    0.0
  end
end
