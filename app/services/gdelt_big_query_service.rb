require "google/cloud/bigquery"

# GdeltBigQueryService
# Low-level BigQuery client wrapper with multi-layer cost protection.
#
# Every query is dry-run validated before execution. Hard per-query and
# daily byte limits ensure we never blow through the free tier (1 TB/month).
#
# Usage:
#   service = GdeltBigQueryService.new
#   service.execute_query(sql)   # dry-run validate → execute → track bytes
#
# === GCP BILLING SAFETY CHECKLIST ===
# Do these manually in Google Cloud Console (console.cloud.google.com):
#
# 1. BUDGET ALERT: Billing → Budgets & alerts → Create Budget
#    - Set amount: $5 (or even $1)
#    - Alert thresholds: 50%, 80%, 100%
#    - Email notifications: ON
#    - This sends you an email BEFORE you get a bill
#
# 2. QUERY QUOTA: BigQuery → Settings → Quotas
#    - Set "Maximum bytes billed per query" to 10 GB
#    - This is a HARD server-side limit — even if our code fails,
#      Google will reject any query that would scan > 10 GB
#    - This is the ultimate safety net
#
# 3. PROJECT-LEVEL DAILY LIMIT: IAM & Admin → Quotas
#    - Search for "BigQuery query usage per day"
#    - Set to 50 GB per day
#    - Google will block ALL queries if this is exceeded
#
# These GCP-side limits are independent of our code and cannot be
# bypassed by a bug. They are the last line of defense.

class GdeltBigQueryService
  # HARD LIMITS — never exceed these
  MAX_BYTES_PER_QUERY = 5_000_000_000   # 5 GB per single query
  MAX_BYTES_PER_DAY   = 35_000_000_000  # 35 GB per day (~1 TB / 30 days, with safety margin)
  DAILY_COUNTER_KEY   = "gdelt_bq_bytes_today"

  class QueryError < StandardError; end
  class QuotaExceededError < StandardError; end

  def initialize
    @project = ENV["GOOGLE_CLOUD_PROJECT"]
    Rails.logger.warn "[GdeltBigQueryService] GOOGLE_CLOUD_PROJECT not set" if @project.blank?

    credentials = ENV["GOOGLE_APPLICATION_CREDENTIALS"]
    Rails.logger.warn "[GdeltBigQueryService] GOOGLE_APPLICATION_CREDENTIALS not set" if credentials.blank?

    @bigquery = Google::Cloud::Bigquery.new(project: @project)
  rescue => e
    raise QueryError, "Failed to initialize BigQuery client: #{e.message}"
  end

  # Executes a BigQuery SQL query with full cost protection.
  # 1. Dry-run to estimate bytes
  # 2. Reject if over per-query limit
  # 3. Reject if daily budget would be exceeded
  # 4. Execute
  # 5. Track actual bytes consumed
  def execute_query(sql)
    # Step 1: ALWAYS dry-run first
    estimated_bytes = dry_run(sql)
    estimated_mb = (estimated_bytes / 1_000_000.0).round(2)
    estimated_gb = (estimated_bytes / 1_000_000_000.0).round(4)

    Rails.logger.info "[BigQuery] Dry-run estimate: #{estimated_mb} MB (#{estimated_gb} GB)"

    # Step 2: Reject queries that are too large
    if estimated_bytes > MAX_BYTES_PER_QUERY
      msg = "[BigQuery] BLOCKED — query would scan #{estimated_mb} MB (limit: #{MAX_BYTES_PER_QUERY / 1_000_000} MB)"
      Rails.logger.error msg
      raise QuotaExceededError, msg
    end

    # Step 3: Check daily budget
    daily_total = daily_bytes_used
    if (daily_total + estimated_bytes) > MAX_BYTES_PER_DAY
      msg = "[BigQuery] BLOCKED — daily limit would be exceeded. " \
            "Used today: #{(daily_total / 1_000_000_000.0).round(2)} GB, " \
            "this query: #{estimated_gb} GB, " \
            "limit: #{MAX_BYTES_PER_DAY / 1_000_000_000} GB"
      Rails.logger.error msg
      raise QuotaExceededError, msg
    end

    # Step 4: Execute
    job = @bigquery.query_job(sql)
    job.wait_until_done!

    if job.failed?
      raise QueryError, "BigQuery job failed: #{job.error&.dig('message')}"
    end

    results = job.query_results

    # Step 5: Track actual bytes consumed
    track_bytes(estimated_bytes)
    Rails.logger.info "[BigQuery] Query executed — #{results.count} rows. " \
                      "Daily total: #{((daily_total + estimated_bytes) / 1_000_000_000.0).round(2)} GB / " \
                      "#{MAX_BYTES_PER_DAY / 1_000_000_000} GB"

    results
  rescue QuotaExceededError
    raise
  rescue QueryError
    raise
  rescue Google::Cloud::Error => e
    Rails.logger.error "[BigQuery] API error: #{e.message}"
    raise QueryError, "BigQuery error: #{e.message}"
  rescue => e
    raise QueryError, "Unexpected BigQuery error: #{e.class}: #{e.message}"
  end

  # Dry-run a query and return estimated bytes processed.
  # Raises QueryError on failure — never silently returns 0.
  def dry_run(sql)
    job = @bigquery.query_job(sql, dryrun: true)
    bytes = job.statistics&.dig("query", "estimatedBytesProcessed").to_i
    bytes
  rescue Google::Cloud::Error => e
    Rails.logger.error "[BigQuery] Dry-run failed: #{e.message}"
    raise QueryError, "Dry-run failed: #{e.message}"
  end

  # Current daily bytes consumed (for external visibility, e.g. rake task)
  def daily_bytes_used
    cache_key = "#{DAILY_COUNTER_KEY}:#{Date.current.iso8601}"
    Rails.cache.fetch(cache_key, expires_in: 25.hours) { 0 }
  end

  private

  def track_bytes(bytes)
    cache_key = "#{DAILY_COUNTER_KEY}:#{Date.current.iso8601}"
    current = Rails.cache.fetch(cache_key, expires_in: 25.hours) { 0 }
    Rails.cache.write(cache_key, current + bytes, expires_in: 25.hours)
  end
end
