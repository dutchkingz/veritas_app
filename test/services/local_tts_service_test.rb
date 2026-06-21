require "test_helper"
require "webmock/minitest"

class LocalTtsServiceTest < ActiveSupport::TestCase
  setup do
    WebMock.disable_net_connect!(allow_localhost: false)
  end

  teardown do
    WebMock.allow_net_connect!
  end

  test "returns audio bytes on successful response" do
    stub_request(:post, "http://localhost:5050/tts")
      .with(body: { text: "Hello world" }.to_json)
      .to_return(status: 200, body: "RIFF\x00\x00\x00\x00WAVEfmt ", headers: { "Content-Type" => "audio/wav" })

    result = LocalTtsService.new(text: "Hello world").call
    assert_equal "RIFF\x00\x00\x00\x00WAVEfmt ", result
  end

  test "returns nil when server is unreachable" do
    stub_request(:post, "http://localhost:5050/tts")
      .to_raise(Errno::ECONNREFUSED)

    result = LocalTtsService.new(text: "Hello world").call
    assert_nil result
  end

  test "returns nil on server error" do
    stub_request(:post, "http://localhost:5050/tts")
      .to_return(status: 500, body: '{"detail":"model crashed"}')

    result = LocalTtsService.new(text: "Hello world").call
    assert_nil result
  end

  test "returns nil when text is blank" do
    result = LocalTtsService.new(text: "").call
    assert_nil result
  end

  test "returns nil on timeout" do
    stub_request(:post, "http://localhost:5050/tts")
      .to_raise(Net::ReadTimeout)

    result = LocalTtsService.new(text: "Hello world").call
    assert_nil result
  end
end
