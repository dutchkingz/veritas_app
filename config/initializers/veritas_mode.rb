# Set default mode to DEMO on app boot.
# VERITAS starts in demo mode by default (no API calls, no Gemini spend).
# Switch to live mode explicitly when needed via console or Command Centre.
# Rescue handles missing solid_cache_entries table during asset precompilation.
Rails.application.config.after_initialize do
  VeritasMode.set!("demo") unless Rails.cache.read(VeritasMode::CACHE_KEY).present?
rescue ActiveRecord::StatementInvalid => e
  Rails.logger.warn "[VeritasMode] Cache unavailable during boot: #{e.message.first(100)}"
end
