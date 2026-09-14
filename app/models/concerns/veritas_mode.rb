module VeritasMode
  CACHE_KEY = "veritas_mode".freeze
  VALID_MODES = %w[demo live].freeze
  VALID_SOURCES = %w[newsapi gdelt_articles gdelt_events].freeze

  class << self
    def current
      Rails.cache.read(CACHE_KEY) || "demo"
    end

    def demo?
      current == "demo"
    end

    def live?
      current == "live"
    end

    def toggle!
      new_mode = demo? ? "live" : "demo"
      Rails.cache.write(CACHE_KEY, new_mode)
      Rails.logger.info "[VeritasMode] Switched to #{new_mode.upcase} mode"
      new_mode
    end

    def set!(mode)
      raise ArgumentError, "Invalid mode: #{mode}" unless VALID_MODES.include?(mode.to_s)
      Rails.cache.write(CACHE_KEY, mode.to_s)
      mode.to_s
    end

    # Check that all required API keys are present for live mode
    def live_mode_ready?
      missing = missing_api_keys
      missing.empty?
    end

    def missing_api_keys
      keys = []
      keys << "NEWS_API_KEY" if ENV["NEWS_API_KEY"].blank?
      keys << "OPENROUTER_API_KEY" if ENV["OPENROUTER_API_KEY"].blank?
      keys
    end

    # NewsAPI daily call tracking
    def api_calls_today
      Rails.cache.read("newsapi_calls:#{Date.today}").to_i
    end

    def api_calls_remaining
      100 - api_calls_today
    end

    def api_limit_reached?
      api_calls_today >= 90
    end

    # --- Per-source toggles ---
    def source_enabled?(source)
      validate_source!(source)
      Rails.cache.read("veritas_source:#{source}") != "disabled"
    end

    def source_disabled?(source)
      !source_enabled?(source)
    end

    def toggle_source!(source)
      validate_source!(source)
      new_state = source_enabled?(source) ? "disabled" : "enabled"
      Rails.cache.write("veritas_source:#{source}", new_state)
      Rails.logger.info "[VeritasMode] Source #{source} → #{new_state.upcase}"
      new_state
    end

    def source_status(source)
      validate_source!(source)
      source_enabled?(source) ? "enabled" : "disabled"
    end

    def all_source_statuses
      VALID_SOURCES.index_with { |s| source_status(s) }
    end

    private

    def validate_source!(source)
      raise ArgumentError, "Unknown source: #{source}. Valid: #{VALID_SOURCES.join(', ')}" unless VALID_SOURCES.include?(source.to_s)
    end
  end
end
