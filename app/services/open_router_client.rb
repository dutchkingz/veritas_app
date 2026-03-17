require 'net/http'
require 'json'

class OpenRouterClient
  API_URL = "https://openrouter.ai/api/v1/chat/completions".freeze
  CREDIT_LIMIT_ERROR_PATTERN = /requires more credits|fewer max_tokens|can only afford/i.freeze

  DEFAULT_MODELS = {
    analyst:          "google/gemini-2.0-flash-001",
    sentinel:         "openai/gpt-4o-mini",
    arbiter:          "anthropic/claude-3.5-haiku",
    briefing:         "anthropic/claude-3.5-haiku",
    voice:            "anthropic/claude-3.5-haiku",
    entity_extractor: "google/gemini-2.0-flash-001"
  }.freeze

  MAX_TOKENS = {
    analyst:          700,
    sentinel:         700,
    arbiter:          900,
    briefing:         600,
    voice:            200,
    entity_extractor: 400
  }.freeze

  def initialize(user: nil)
    @api_key      = ENV.fetch('OPENROUTER_API_KEY')
    @model_config = user&.model_config
  end

  # Send a prompt to a specific agent model and return parsed JSON
  def chat(agent_role, system_prompt, user_prompt, expect_json: true)
    model      = resolve_model(agent_role)
    max_tokens = MAX_TOKENS.fetch(agent_role.to_sym, 700)

    response = request_chat(
      model: model,
      system_prompt: system_prompt,
      user_prompt: user_prompt,
      expect_json: expect_json,
      max_tokens: max_tokens
    )

    data = JSON.parse(response.body)
    content = data.dig("choices", 0, "message", "content")

    if expect_json
      # Strip markdown code fences if the model wraps JSON in ```json blocks
      cleaned = content.gsub(/\A```json\s*/i, '').gsub(/```\s*\z/, '').strip
      JSON.parse(cleaned)
    else
      content
    end
  end

  # Generate a 1536-dimensional vector embedding for semantic search
  def embed(text)
    uri = URI("https://openrouter.ai/api/v1/embeddings")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Post.new(uri)
    request["Authorization"] = "Bearer #{@api_key}"
    request["Content-Type"]  = "application/json"
    request["HTTP-Referer"]  = "https://veritas-app-314a53c53525.herokuapp.com/"
    request["X-Title"]       = "VERITAS Intelligence Platform"
    
    # OpenRouter fully supports OpenAI's native embedding endpoint format
    request.body = {
      model: "text-embedding-3-small", 
      input: text
    }.to_json

    response = http.request(request)

    unless response.is_a?(Net::HTTPSuccess)
      raise "OpenRouter Embedding API error (#{response.code}): #{response.body}"
    end

    data = JSON.parse(response.body)
    data.dig("data", 0, "embedding") # Returns the Array of 1536 floats
  end

  private

  def resolve_model(agent_role)
    role = agent_role.to_sym
    if @model_config
      configured = @model_config.model_for(role)
      return DEFAULT_MODELS.fetch(role, agent_role.to_s) if configured == "custom"
      return configured if configured.present?
    end
    DEFAULT_MODELS.fetch(role, agent_role.to_s)
  end

  def effective_api_key
    @model_config&.effective_api_key || @api_key
  end

  def effective_api_url
    @model_config&.effective_endpoint&.then { |ep| "#{ep.chomp('/')}/chat/completions" } || API_URL
  end

  def request_chat(model:, system_prompt:, user_prompt:, expect_json:, max_tokens:)
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

    uri = URI(effective_api_url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.read_timeout = 60

    request = Net::HTTP::Post.new(uri)
    request["Authorization"] = "Bearer #{effective_api_key}"
    request["Content-Type"]  = "application/json"
    request["HTTP-Referer"]  = "https://veritas-app-314a53c53525.herokuapp.com/"
    request["X-Title"]       = "VERITAS Intelligence Platform"
    request.body = body.to_json

    response = http.request(request)
    return response if response.is_a?(Net::HTTPSuccess)

    if response.code.to_i == 402 && response.body.match?(CREDIT_LIMIT_ERROR_PATTERN) && max_tokens > 250
      reduced_max_tokens = [max_tokens - 200, 250].max
      Rails.logger.warn "[OpenRouter] Retrying #{model} with lower max_tokens=#{reduced_max_tokens} after credit-limit response."
      return request_chat(
        model: model,
        system_prompt: system_prompt,
        user_prompt: user_prompt,
        expect_json: expect_json,
        max_tokens: reduced_max_tokens
      )
    end

    raise "OpenRouter API error (#{response.code}): #{response.body}"
  end
end
