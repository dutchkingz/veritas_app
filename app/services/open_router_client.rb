require 'net/http'
require 'json'

class OpenRouterClient
  API_URL = "https://openrouter.ai/api/v1/chat/completions".freeze

  MODELS = {
    analyst: "google/gemini-2.0-flash-001",
    sentinel: "openai/gpt-4o-mini",
    arbiter: "anthropic/claude-3.5-haiku"
  }.freeze

  def initialize
    @api_key = ENV.fetch('OPENROUTER_API_KEY')
  end

  # Send a prompt to a specific agent model and return parsed JSON
  def chat(agent_role, system_prompt, user_prompt, expect_json: true)
    model = MODELS.fetch(agent_role)

    body = {
      model: model,
      messages: [
        { role: "system", content: system_prompt },
        { role: "user",   content: user_prompt }
      ],
      temperature: 0.3,
      max_tokens: 2000
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

    raise "OpenRouter API error (#{response.code}): #{response.body}" unless response.is_a?(Net::HTTPSuccess)

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
end
