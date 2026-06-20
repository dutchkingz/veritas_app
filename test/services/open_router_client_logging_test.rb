require "test_helper"
require "ostruct"

class OpenRouterClientLoggingTest < ActiveSupport::TestCase
  setup do
    ENV["OPENROUTER_API_KEY"] = "test-key"
  end

  test "successful API call creates an ApiUsageLog with status success" do
    fake_response = OpenStruct.new(
      code: "200",
      body: {
        choices: [{ message: { content: '{"result": "ok"}' } }],
        usage: { prompt_tokens: 100, completion_tokens: 50, total_cost: 0.001 }
      }.to_json
    )

    client = OpenRouterClient.new
    client.define_singleton_method(:request_chat) { |**_| fake_response }
    client.define_singleton_method(:resolve_model) { |_| "google/gemini-2.5-flash" }

    assert_difference "ApiUsageLog.count", 1 do
      result = client.chat(:analyst, "system", "user")
      assert_equal({ "result" => "ok" }, result)
    end

    log = ApiUsageLog.last
    assert_equal "success", log.status
    assert_equal "google/gemini-2.5-flash", log.model
    assert_equal "analyst", log.agent_role
    assert_equal 100, log.input_tokens
    assert_equal 50, log.output_tokens
    assert_in_delta 0.001, log.estimated_cost.to_f, 0.0001
    assert_equal 200, log.http_status
  end

  test "failed API call creates an ApiUsageLog with status error" do
    client = OpenRouterClient.new
    client.define_singleton_method(:resolve_model) { |_| "google/gemini-2.5-flash" }
    client.define_singleton_method(:request_chat) { |**_| raise "OpenRouter API error (500): Internal Server Error" }

    assert_difference "ApiUsageLog.count", 1 do
      assert_raises(RuntimeError) do
        client.chat(:analyst, "system", "user")
      end
    end

    log = ApiUsageLog.last
    assert_equal "error", log.status
    assert_equal "google/gemini-2.5-flash", log.model
    assert_equal "analyst", log.agent_role
    assert_equal 500, log.http_status
    assert_includes log.error_message, "OpenRouter API error"
    assert_nil log.input_tokens
    assert_nil log.output_tokens
  end

  test "logging failure does not break the API call" do
    fake_response = OpenStruct.new(
      code: "200",
      body: {
        choices: [{ message: { content: '{"result": "ok"}' } }],
        usage: { prompt_tokens: 100, completion_tokens: 50, total_cost: 0.001 }
      }.to_json
    )

    client = OpenRouterClient.new
    client.define_singleton_method(:request_chat) { |**_| fake_response }
    client.define_singleton_method(:resolve_model) { |_| "google/gemini-2.5-flash" }

    # Override log_api_usage to simulate a logging failure
    client.define_singleton_method(:log_api_usage) { |**_| raise ActiveRecord::ActiveRecordError, "DB down" }

    # Should still return the result — the rescue in chat catches and re-raises,
    # but log_api_usage itself is wrapped in rescue, so this tests that internal rescue
    # Actually, since we override the whole method, we need to test the real rescue.
    # Let's instead stub ApiUsageLog.create! to fail.
    # Reset to original log_api_usage so internal rescue is tested:
    client = OpenRouterClient.new
    client.define_singleton_method(:request_chat) { |**_| fake_response }
    client.define_singleton_method(:resolve_model) { |_| "google/gemini-2.5-flash" }

    original_create = ApiUsageLog.method(:create!)
    ApiUsageLog.define_singleton_method(:create!) { |**_| raise ActiveRecord::ActiveRecordError, "DB down" }

    begin
      result = client.chat(:analyst, "system", "user")
      assert_equal({ "result" => "ok" }, result)
    ensure
      ApiUsageLog.define_singleton_method(:create!, original_create)
    end
  end
end
