class UserModelConfig < ApplicationRecord
  belongs_to :user

  AVAILABLE_MODELS = {
    analyst:  [
      "google/gemini-2.0-flash-001",
      "openai/gpt-4o-mini",
      "anthropic/claude-3.5-haiku",
      "meta-llama/llama-3.3-70b-instruct",
      "custom"
    ],
    sentinel: [
      "openai/gpt-4o-mini",
      "google/gemini-2.0-flash-001",
      "anthropic/claude-3.5-haiku",
      "meta-llama/llama-3.3-70b-instruct",
      "custom"
    ],
    arbiter: [
      "anthropic/claude-3.5-haiku",
      "openai/gpt-4o-mini",
      "google/gemini-2.0-flash-001",
      "meta-llama/llama-3.3-70b-instruct",
      "custom"
    ],
    briefing: [
      "anthropic/claude-3.5-haiku",
      "openai/gpt-4o-mini",
      "google/gemini-2.0-flash-001",
      "custom"
    ],
    voice: [
      "anthropic/claude-3.5-haiku",
      "openai/gpt-4o-mini",
      "google/gemini-2.0-flash-001",
      "custom"
    ]
  }.freeze

  ROLE_LABELS = {
    analyst:  "Analyst Agent",
    sentinel: "Sentinel Agent",
    arbiter:  "Arbiter Agent",
    briefing: "Briefing Generator",
    voice:    "Voice Briefing"
  }.freeze

  validates :analyst_model, :sentinel_model, :arbiter_model, :briefing_model, :voice_model, presence: true
  validate :custom_endpoint_required_when_active

  # Returns the effective model ID for a given agent role.
  # Falls back to the system default if config doesn't define it.
  def model_for(role)
    send("#{role}_model") || self.class.default_model(role)
  end

  # Returns the API key to use: custom if configured, otherwise nil (use system key)
  def effective_api_key
    use_custom_endpoint? && custom_api_key_encrypted.present? ? custom_api_key_encrypted : nil
  end

  # Returns the base URL: custom endpoint if configured, otherwise nil (use OpenRouter)
  def effective_endpoint
    use_custom_endpoint? && custom_endpoint_url.present? ? custom_endpoint_url : nil
  end

  def self.default_model(role)
    {
      analyst:  "google/gemini-2.0-flash-001",
      sentinel: "openai/gpt-4o-mini",
      arbiter:  "anthropic/claude-3.5-haiku",
      briefing: "anthropic/claude-3.5-haiku",
      voice:    "anthropic/claude-3.5-haiku"
    }[role.to_sym]
  end

  private

  def custom_endpoint_required_when_active
    return unless use_custom_endpoint?
    errors.add(:custom_endpoint_url, "is required when using a custom endpoint") if custom_endpoint_url.blank?
  end
end
