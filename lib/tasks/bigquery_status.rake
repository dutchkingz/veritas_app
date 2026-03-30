namespace :veritas do
  desc "Show BigQuery usage stats for today"
  task bq_status: :environment do
    cache_key = "#{GdeltBigQueryService::DAILY_COUNTER_KEY}:#{Date.current.iso8601}"
    bytes_today = Rails.cache.fetch(cache_key) { 0 }
    gb_today = (bytes_today / 1_000_000_000.0).round(4)
    daily_limit_gb = GdeltBigQueryService::MAX_BYTES_PER_DAY / 1_000_000_000
    monthly_estimate_gb = gb_today * 30

    puts "=" * 50
    puts "VERITAS BigQuery Usage Report"
    puts "=" * 50
    puts "Date:             #{Date.current}"
    puts "Used today:       #{gb_today} GB"
    puts "Daily limit:      #{daily_limit_gb} GB"
    puts "Remaining:        #{(daily_limit_gb - gb_today).round(4)} GB"
    puts "Monthly estimate: #{monthly_estimate_gb.round(2)} GB (free tier: 1,000 GB)"
    puts "Status:           #{gb_today > daily_limit_gb * 0.8 ? '⚠️  WARNING' : '✅ OK'}"
    puts "=" * 50
  end
end
