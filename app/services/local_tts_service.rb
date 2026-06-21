class LocalTtsService
  URL = "http://localhost:5050/tts".freeze

  def initialize(text:)
    @text = text
  end

  def call
    return nil if @text.blank?

    uri = URI(URL)
    http = Net::HTTP.new(uri.host, uri.port)
    http.open_timeout = 5
    http.read_timeout = 60

    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"
    request.body = { text: @text }.to_json

    response = http.request(request)

    if response.code == "200"
      response.body
    else
      Rails.logger.warn "[LocalTTS] Server returned #{response.code}: #{response.body.first(200)}"
      nil
    end
  rescue Errno::ECONNREFUSED, Net::OpenTimeout, Net::ReadTimeout, SocketError => e
    Rails.logger.warn "[LocalTTS] Unavailable: #{e.class} — falling back"
    nil
  rescue StandardError => e
    Rails.logger.error "[LocalTTS] Unexpected error: #{e.class} #{e.message}"
    nil
  end
end
