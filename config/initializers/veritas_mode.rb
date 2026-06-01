# Set default mode to LIVE on app boot.
# VERITAS runs in live mode by default (fetching articles, running analysis).
# Switch to demo mode only when explicitly needed (e.g. demos, testing).
# Rescue handles missing solid_cache_entries table during asset precompilation.
Rails.application.config.after_initialize do
  VeritasMode.set!("live") unless Rails.cache.read(VeritasMode::CACHE_KEY).present?
rescue ActiveRecord::StatementInvalid => e
  Rails.logger.warn "[VeritasMode] Cache unavailable during boot: #{e.message.first(100)}"
end
