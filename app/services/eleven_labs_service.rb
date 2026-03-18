class ElevenLabsService
  API_URL = "https://api.elevenlabs.io/v1/text-to-speech".freeze
  DEFAULT_MODEL = "eleven_multilingual_v2".freeze

  # Maximum stability + low similarity = flat, detached, HAL-like monotone
  DEFAULT_VOICE_SETTINGS = {
    stability: 1.0,
    similarity_boost: 0.30,
    style: 0.0,
    use_speaker_boost: false
  }.freeze

  def initialize(text:, voice_id: nil)
    @text     = text
    @voice_id = voice_id || ENV.fetch("ELEVENLABS_VOICE_ID", "pNInz6obpgDQGcFmaJgB")
    @api_key  = ENV["ELEVENLABS_API_KEY"]
  end

  def call
    return nil if @api_key.blank? || @text.blank?

    uri  = URI("#{API_URL}/#{@voice_id}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl     = true
    http.open_timeout = 5
    http.read_timeout = 30

    request = Net::HTTP::Post.new(uri)
    request["xi-api-key"]  = @api_key
    request["Content-Type"] = "application/json"
    request["Accept"]       = "audio/mpeg"
    request.body = {
      text: @text,
      model_id: DEFAULT_MODEL,
      voice_settings: DEFAULT_VOICE_SETTINGS
    }.to_json

    response = http.request(request)

    if response.code == "200"
      response.body
    else
      Rails.logger.error "[ElevenLabs] TTS failed: #{response.code} — #{response.body.first(200)}"
      nil
    end
  rescue StandardError => e
    Rails.logger.error "[ElevenLabs] TTS error: #{e.class} #{e.message}"
    nil
  end
end
