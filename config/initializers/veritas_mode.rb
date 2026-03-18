# Set default mode to DEMO on app boot.
# This ensures the app always starts in demo mode (zero external API calls)
# until explicitly switched to live mode via the UI toggle.
# Rescue handles missing solid_cache_entries table during asset precompilation.
Rails.application.config.after_initialize do
  VeritasMode.set!("demo") unless Rails.cache.read(VeritasMode::CACHE_KEY).present?
rescue ActiveRecord::StatementInvalid => e
  Rails.logger.warn "[VeritasMode] Cache unavailable during boot: #{e.message.first(100)}"
end
