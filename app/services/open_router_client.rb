require 'net/http'
require 'json'

class OpenRouterClient
  API_URL = "https://openrouter.ai/api/v1/chat/completions".freeze
  CREDIT_LIMIT_ERROR_PATTERN = /requires more credits|fewer max_tokens|can only afford/i.freeze

  MODELS = {
    analyst: "google/gemini-2.0-flash-001",
    sentinel: "openai/gpt-4o-mini",
    arbiter: "anthropic/claude-3.5-haiku"
  }.freeze

  MAX_TOKENS = {
    analyst: 700,
    sentinel: 700,
    arbiter: 900
  }.freeze

  def initialize
    @api_key = ENV.fetch('OPENROUTER_API_KEY')
  end

  # Send a prompt to a specific agent model and return parsed JSON
  def chat(agent_role, system_prompt, user_prompt, expect_json: true)
    model = MODELS.fetch(agent_role) { agent_role.to_s }
    max_tokens = MAX_TOKENS.fetch(agent_role, 700)

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
    request["HTTP-Referer"]  = "https://veritas-app.com"
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

    uri = URI(API_URL)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = 60

    request = Net::HTTP::Post.new(uri)
    request["Authorization"] = "Bearer #{@api_key}"
    request["Content-Type"]  = "application/json"
    request["HTTP-Referer"]  = "https://veritas-app.com"
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
