require 'net/http'
require 'json'

class OpenRouterClient
  # Raised on HTTP 429 — caller can retry_on this with exponential backoff.
  class RateLimitError < StandardError; end

  # ── OpenRouter config ──────────────────────────────────────────
  OPENROUTER_API_URL = "https://openrouter.ai/api/v1/chat/completions".freeze
  CREDIT_LIMIT_ERROR_PATTERN = /requires more credits|fewer max_tokens|can only afford/i.freeze

  # ── Google Gemini config ───────────────────────────────────────
  GEMINI_BASE_URL = "https://generativelanguage.googleapis.com/v1beta".freeze
  GEMINI_EMBED_MODEL = "gemini-embedding-001".freeze
  GEMINI_EMBED_DIMENSIONS = 768

  # Gemini Flash pricing (per token) — used to estimate cost since Google doesn't return it
  GEMINI_INPUT_COST_PER_TOKEN  = 0.10 / 1_000_000  # $0.10 per 1M input tokens
  GEMINI_OUTPUT_COST_PER_TOKEN = 0.40 / 1_000_000  # $0.40 per 1M output tokens

  DEFAULT_MODELS = {
    analyst:           "gemini-3-flash-preview",
    sentinel:          "gemini-3-flash-preview",
    arbiter:           "gemini-3-flash-preview",
    briefing:          "gemini-3-flash-preview",
    voice:             "gemini-3-flash-preview",
    entity_extractor:  "gemini-3-flash-preview",
    relevance_filter:  "gemini-3-flash-preview"
  }.freeze

  MAX_TOKENS = {
    analyst:          700,
    sentinel:         700,
    arbiter:          900,
    briefing:         600,
    voice:            200,
    entity_extractor: 400,
    relevance_filter: 60
  }.freeze

  def initialize(user: nil)
    @google_api_key    = ENV['GOOGLE_API_KEY']
    @openrouter_key    = ENV['OPENROUTER_API_KEY']
    @use_gemini        = @google_api_key.present?
    @model_config      = user&.model_config
  end

  # Send a prompt to a specific agent model and return parsed JSON
  def chat(agent_role, system_prompt, user_prompt, expect_json: true)
    model      = resolve_model(agent_role)
    max_tokens = MAX_TOKENS.fetch(agent_role.to_sym, 700)

    begin
      if @use_gemini
        gemini_chat(
          model: model,
          system_prompt: system_prompt,
          user_prompt: user_prompt,
          expect_json: expect_json,
          max_tokens: max_tokens,
          agent_role: agent_role
        )
      else
        openrouter_chat(
          model: model,
          system_prompt: system_prompt,
          user_prompt: user_prompt,
          expect_json: expect_json,
          max_tokens: max_tokens,
          agent_role: agent_role
        )
      end
    rescue => e
      log_api_usage_error(model: model, agent_role: agent_role, error: e)
      raise
    end
  end

  # Generate a vector embedding for semantic search
  def embed(text)
    if @use_gemini
      gemini_embed(text)
    else
      openrouter_embed(text)
    end
  end

  # Expose current embedding dimensions so callers can validate
  def self.embedding_dimensions
    ENV['GOOGLE_API_KEY'].present? ? GEMINI_EMBED_DIMENSIONS : 1536
  end

  private

  # ── Google Gemini implementation ─────────────────────────────

  def gemini_chat(model:, system_prompt:, user_prompt:, expect_json:, max_tokens:, agent_role:)
    url = "#{GEMINI_BASE_URL}/models/#{model}:generateContent?key=#{@google_api_key}"
    uri = URI(url)

    generation_config = {
      temperature: 0.3,
      maxOutputTokens: max_tokens,
      thinkingConfig: { thinkingBudget: 0 }
    }
    generation_config[:responseMimeType] = "application/json" if expect_json

    body = {
      systemInstruction: { parts: [{ text: system_prompt }] },
      contents: [{ role: "user", parts: [{ text: user_prompt }] }],
      generationConfig: generation_config
    }

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = 60

    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"
    request.body = body.to_json

    response = http.request(request)

    raise RateLimitError, "Gemini rate limit (429): #{response.body}" if response.code.to_i == 429

    unless response.is_a?(Net::HTTPSuccess)
      raise "Gemini API error (#{response.code}): #{response.body}"
    end

    data = JSON.parse(response.body)

    # Log usage with estimated cost
    usage = data["usageMetadata"] || {}
    input_tokens = usage["promptTokenCount"].to_i
    output_tokens = usage["candidatesTokenCount"].to_i
    estimated_cost = (input_tokens * GEMINI_INPUT_COST_PER_TOKEN) +
                     (output_tokens * GEMINI_OUTPUT_COST_PER_TOKEN)

    log_api_usage(
      model: model,
      agent_role: agent_role,
      response: response,
      data: {
        "usage" => {
          "prompt_tokens" => input_tokens,
          "completion_tokens" => output_tokens,
          "total_cost" => estimated_cost
        }
      }
    )

    content = data.dig("candidates", 0, "content", "parts", 0, "text")

    if expect_json
      cleaned = content.gsub(/\A```json\s*/i, '').gsub(/```\s*\z/, '').strip
      JSON.parse(cleaned)
    else
      content
    end
  end

  def gemini_embed(text)
    url = "#{GEMINI_BASE_URL}/models/#{GEMINI_EMBED_MODEL}:embedContent?key=#{@google_api_key}"
    uri = URI(url)

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"
    request.body = {
      model: "models/#{GEMINI_EMBED_MODEL}",
      content: { parts: [{ text: text }] },
      outputDimensionality: GEMINI_EMBED_DIMENSIONS
    }.to_json

    response = http.request(request)

    unless response.is_a?(Net::HTTPSuccess)
      raise "Gemini Embedding API error (#{response.code}): #{response.body}"
    end

    data = JSON.parse(response.body)
    data.dig("embedding", "values")
  end

  # ── OpenRouter implementation (fallback) ─────────────────────

  def openrouter_chat(model:, system_prompt:, user_prompt:, expect_json:, max_tokens:, agent_role:)
    # Prefix model names for OpenRouter format
    or_model = model.include?("/") ? model : "google/#{model}"

    response = openrouter_request_chat(
      model: or_model,
      system_prompt: system_prompt,
      user_prompt: user_prompt,
      expect_json: expect_json,
      max_tokens: max_tokens
    )

    data = JSON.parse(response.body)
    log_api_usage(model: or_model, agent_role: agent_role, response: response, data: data)

    content = data.dig("choices", 0, "message", "content")

    if expect_json
      cleaned = content.gsub(/\A```json\s*/i, '').gsub(/```\s*\z/, '').strip
      JSON.parse(cleaned)
    else
      content
    end
  end

  def openrouter_embed(text)
    uri = URI("https://openrouter.ai/api/v1/embeddings")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Post.new(uri)
    request["Authorization"] = "Bearer #{@openrouter_key}"
    request["Content-Type"]  = "application/json"
    request["HTTP-Referer"]  = "https://veritas-app-314a53c53525.herokuapp.com/"
    request["X-Title"]       = "VERITAS Intelligence Platform"

    request.body = {
      model: "text-embedding-3-small",
      input: text
    }.to_json

    response = http.request(request)

    unless response.is_a?(Net::HTTPSuccess)
      raise "OpenRouter Embedding API error (#{response.code}): #{response.body}"
    end

    data = JSON.parse(response.body)
    data.dig("data", 0, "embedding")
  end

  # ── Shared helpers ───────────────────────────────────────────

  def resolve_model(agent_role)
    role = agent_role.to_sym
    if @model_config && !@use_gemini
      configured = @model_config.model_for(role)
      return DEFAULT_MODELS.fetch(role, agent_role.to_s) if configured == "custom"
      return configured if configured.present?
    end
    DEFAULT_MODELS.fetch(role, agent_role.to_s)
  end

  def openrouter_request_chat(model:, system_prompt:, user_prompt:, expect_json:, max_tokens:)
    body = {
      model: model,
      messages: [
        { role: "system", content: system_prompt },
        { role: "user",   content: user_prompt }
      ],
      temperature: 0.3,
      max_tokens: max_tokens
    }
    body[:response_format] = { type: "json_object" } if expect_json

    uri = URI(OPENROUTER_API_URL)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = 60

    request = Net::HTTP::Post.new(uri)
    request["Authorization"] = "Bearer #{@openrouter_key}"
    request["Content-Type"]  = "application/json"
    request["HTTP-Referer"]  = "https://veritas-app-314a53c53525.herokuapp.com/"
    request["X-Title"]       = "VERITAS Intelligence Platform"
    request.body = body.to_json

    response = http.request(request)
    return response if response.is_a?(Net::HTTPSuccess)

    raise RateLimitError, "OpenRouter rate limit (429): #{response.body}" if response.code.to_i == 429

    if response.code.to_i == 402 && response.body.match?(CREDIT_LIMIT_ERROR_PATTERN) && max_tokens > 250
      reduced_max_tokens = [max_tokens - 200, 250].max
      Rails.logger.warn "[OpenRouter] Retrying #{model} with lower max_tokens=#{reduced_max_tokens}"
      return openrouter_request_chat(
        model: model,
        system_prompt: system_prompt,
        user_prompt: user_prompt,
        expect_json: expect_json,
        max_tokens: reduced_max_tokens
      )
    end

    raise "OpenRouter API error (#{response.code}): #{response.body}"
  end

  def log_api_usage(model:, agent_role:, response:, data:)
    ApiUsageLog.create!(
      model: model,
      agent_role: agent_role.to_s,
      input_tokens: data.dig("usage", "prompt_tokens"),
      output_tokens: data.dig("usage", "completion_tokens"),
      estimated_cost: data.dig("usage", "total_cost"),
      status: "success",
      error_message: nil,
      http_status: response.code.to_i
    )
  rescue => e
    Rails.logger.warn "[ApiUsageLog] Failed to log API usage: #{e.message}"
  end

  def log_api_usage_error(model:, agent_role:, error:)
    http_status = error.message[/\((\d+)\)/, 1]&.to_i
    ApiUsageLog.create!(
      model: model,
      agent_role: agent_role.to_s,
      input_tokens: nil,
      output_tokens: nil,
      estimated_cost: nil,
      status: "error",
      error_message: error.message.truncate(500),
      http_status: http_status
    )
  rescue => e
    Rails.logger.warn "[ApiUsageLog] Failed to log API error: #{e.message}"
  end
end
