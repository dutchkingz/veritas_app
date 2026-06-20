class SystemHealthService
  DB_LIMIT_BYTES = 500.megabytes

  def call
    {
      gauges: build_gauges,
      kpis: build_kpis,
      alerts: build_alerts,
      recent_errors: build_recent_errors,
      api_breakdown: build_api_breakdown,
      db_stats: build_db_stats,
      ingestion: build_ingestion_stats
    }
  end

  private

  def build_gauges
    db_size = db_size_bytes
    {
      db_storage: {
        used_bytes: db_size,
        limit_bytes: DB_LIMIT_BYTES,
        percentage: (db_size.to_f / DB_LIMIT_BYTES * 100).round(1)
      },
      api_credits: {
        spent_today: ApiUsageLog.total_cost_today,
        spent_month: ApiUsageLog.where("created_at >= ?", Time.current.beginning_of_month).sum(:estimated_cost).to_f
      },
      data_transfer: {
        limit_gb: 5.0
      }
    }
  end

  def build_kpis
    articles_today_count = Article.where("fetched_at >= ?", Time.current.beginning_of_day).count
    analyzed_today = AiAnalysis.where("created_at >= ?", Time.current.beginning_of_day).count
    pending = Article.left_joins(:ai_analysis).where(ai_analyses: { id: nil }).count
    job_stats = job_success_stats

    {
      api_spend_today: ApiUsageLog.total_cost_today,
      api_spend_month: ApiUsageLog.where("created_at >= ?", Time.current.beginning_of_month).sum(:estimated_cost).to_f,
      job_success_rate: job_stats[:rate],
      job_succeeded: job_stats[:succeeded],
      job_total: job_stats[:total],
      db_size_bytes: db_size_bytes,
      db_percentage: (db_size_bytes.to_f / DB_LIMIT_BYTES * 100).round(1),
      articles_today: articles_today_count,
      articles_analyzed: analyzed_today,
      articles_pending: pending
    }
  end

  def build_alerts
    alerts = []
    db_pct = (db_size_bytes.to_f / DB_LIMIT_BYTES * 100).round(1)

    if db_pct > 80
      alerts << { level: :red, message: "Database storage at #{db_pct}% of 500 MB limit" }
    elsif db_pct > 60
      alerts << { level: :amber, message: "Database storage at #{db_pct}% of 500 MB limit" }
    end

    job_stats = job_success_stats
    if job_stats[:total] > 0 && job_stats[:rate] < 50
      alerts << { level: :red, message: "Job success rate #{job_stats[:rate]}% — #{job_stats[:succeeded]}/#{job_stats[:total]} in last 24h" }
    end

    last_fetch = Article.maximum(:fetched_at)
    if last_fetch && last_fetch < 2.hours.ago
      alerts << { level: :amber, message: "No articles fetched in last 2 hours (last: #{time_ago_in_words(last_fetch)})" }
    end

    recent_api_errors = ApiUsageLog.failed.where("created_at >= ?", 1.hour.ago).count
    if recent_api_errors > 10
      alerts << { level: :red, message: "#{recent_api_errors} API errors in the last hour" }
    end

    alerts << { level: :green, message: "Systems nominal" } if alerts.empty?
    alerts
  end

  def build_recent_errors
    api_errors = ApiUsageLog.failed.order(created_at: :desc).limit(10).map do |log|
      {
        source: "API",
        label: "#{log.agent_role} → #{log.model}",
        message: log.error_message.to_s.truncate(100),
        http_status: log.http_status,
        timestamp: log.created_at
      }
    end

    job_errors = SolidQueue::FailedExecution.order(created_at: :desc).limit(10).map do |fe|
      {
        source: "Job",
        label: fe.job&.class_name || "Unknown",
        message: fe.error.to_s.truncate(100),
        http_status: nil,
        timestamp: fe.created_at
      }
    end

    (api_errors + job_errors).sort_by { |e| e[:timestamp] }.reverse.first(20)
  end

  def build_api_breakdown
    ApiUsageLog.today.group(:model).select(
      "model",
      "COUNT(*) as call_count",
      "SUM(estimated_cost) as total_cost",
      "SUM(input_tokens) as total_input_tokens",
      "SUM(output_tokens) as total_output_tokens"
    ).order("total_cost DESC NULLS LAST").map do |row|
      {
        model: row.model,
        call_count: row.call_count,
        total_cost: row.total_cost.to_f,
        total_input_tokens: row.total_input_tokens.to_i,
        total_output_tokens: row.total_output_tokens.to_i
      }
    end
  end

  def build_db_stats
    tables = ActiveRecord::Base.connection.execute(<<~SQL).to_a
      SELECT relname AS table_name,
             n_live_tup AS row_count,
             pg_total_relation_size(quote_ident(relname)) AS size_bytes
      FROM pg_stat_user_tables
      ORDER BY pg_total_relation_size(quote_ident(relname)) DESC
      LIMIT 10
    SQL

    {
      total_size_bytes: db_size_bytes,
      total_size_pretty: pretty_bytes(db_size_bytes),
      tables: tables.map do |t|
        {
          name: t["table_name"],
          row_count: t["row_count"].to_i,
          size_bytes: t["size_bytes"].to_i,
          size_pretty: pretty_bytes(t["size_bytes"].to_i)
        }
      end
    }
  end

  def build_ingestion_stats
    {
      last_fetch: Article.maximum(:fetched_at),
      articles_today: Article.where("fetched_at >= ?", Time.current.beginning_of_day).count,
      articles_analyzed: AiAnalysis.where("created_at >= ?", Time.current.beginning_of_day).count,
      articles_pending: Article.left_joins(:ai_analysis).where(ai_analyses: { id: nil }).count,
      sources: active_sources
    }
  end

  def db_size_bytes
    @db_size_bytes ||= ActiveRecord::Base.connection
      .select_value("SELECT pg_database_size(current_database())").to_i
  end

  def job_success_stats
    since = 24.hours.ago
    total = SolidQueue::Job.where("created_at >= ?", since).count
    failed = SolidQueue::FailedExecution.where("created_at >= ?", since).count
    succeeded = total - failed
    rate = total > 0 ? (succeeded.to_f / total * 100).round(1) : 100.0
    { succeeded: succeeded, total: total, rate: rate }
  end

  def active_sources
    sources = []
    sources << "NewsAPI" if Article.where(data_source: "newsapi").exists?
    sources << "GDELT" if Article.where("headline LIKE ?", "%— GDELT").exists?
    sources
  end

  def pretty_bytes(bytes)
    if bytes >= 1.gigabyte
      "#{(bytes.to_f / 1.gigabyte).round(2)} GB"
    elsif bytes >= 1.megabyte
      "#{(bytes.to_f / 1.megabyte).round(1)} MB"
    elsif bytes >= 1.kilobyte
      "#{(bytes.to_f / 1.kilobyte).round(1)} KB"
    else
      "#{bytes} B"
    end
  end

  def time_ago_in_words(time)
    seconds = (Time.current - time).to_i
    case seconds
    when 0..59 then "#{seconds}s ago"
    when 60..3599 then "#{seconds / 60}m ago"
    when 3600..86399 then "#{seconds / 3600}h ago"
    else "#{seconds / 86400}d ago"
    end
  end
end
