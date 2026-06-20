require "test_helper"

class SystemHealthServiceTest < ActiveSupport::TestCase
  setup do
    @service = SystemHealthService.new
  end

  test "call returns a hash with all expected top-level keys" do
    result = @service.call
    assert_kind_of Hash, result
    %i[gauges kpis alerts recent_errors api_breakdown db_stats ingestion].each do |key|
      assert result.key?(key), "Missing key: #{key}"
    end
  end

  test "kpis includes api_spend_today" do
    ApiUsageLog.create!(model: "test", agent_role: "analyst", status: "success", estimated_cost: 0.005)
    ApiUsageLog.create!(model: "test", agent_role: "sentinel", status: "success", estimated_cost: 0.003)
    result = @service.call
    assert_in_delta 0.008, result[:kpis][:api_spend_today], 0.0001
  end

  test "kpis includes articles_today counts" do
    result = @service.call
    assert result[:kpis].key?(:articles_today)
    assert result[:kpis].key?(:articles_analyzed)
    assert result[:kpis].key?(:articles_pending)
  end

  test "alerts returns array" do
    result = @service.call
    assert_kind_of Array, result[:alerts]
  end

  test "alerts includes nominal message when no problems" do
    result = @service.call
    assert result[:alerts].any? { |a| a[:level] == :green }
  end

  test "api_breakdown groups by model" do
    ApiUsageLog.create!(model: "google/gemini-2.5-flash", agent_role: "analyst", status: "success", estimated_cost: 0.001)
    ApiUsageLog.create!(model: "google/gemini-2.5-flash", agent_role: "arbiter", status: "success", estimated_cost: 0.002)
    ApiUsageLog.create!(model: "openai/gpt-4o-mini", agent_role: "sentinel", status: "success", estimated_cost: 0.001)
    result = @service.call
    gemini = result[:api_breakdown].find { |r| r[:model] == "google/gemini-2.5-flash" }
    assert_equal 2, gemini[:call_count]
    assert_in_delta 0.003, gemini[:total_cost], 0.0001
  end

  test "db_stats includes total size" do
    result = @service.call
    assert result[:db_stats].key?(:total_size_bytes)
    assert result[:db_stats].key?(:tables)
  end

  test "ingestion includes last_fetch and counts" do
    result = @service.call
    %i[last_fetch articles_today articles_analyzed articles_pending].each do |key|
      assert result[:ingestion].key?(key), "Missing ingestion key: #{key}"
    end
  end

  test "gauges includes db_storage with percentage" do
    result = @service.call
    db_gauge = result[:gauges][:db_storage]
    assert db_gauge.key?(:used_bytes)
    assert db_gauge.key?(:limit_bytes)
    assert db_gauge.key?(:percentage)
  end
end
