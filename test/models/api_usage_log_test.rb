require "test_helper"

class ApiUsageLogTest < ActiveSupport::TestCase
  test "today scope returns only records from today" do
    old = ApiUsageLog.create!(model: "test", agent_role: "analyst", status: "success", created_at: 2.days.ago)
    recent = ApiUsageLog.create!(model: "test", agent_role: "analyst", status: "success")

    assert_includes ApiUsageLog.today, recent
    assert_not_includes ApiUsageLog.today, old
  end

  test "successful scope filters by success status" do
    ok = ApiUsageLog.create!(model: "test", agent_role: "analyst", status: "success")
    fail_log = ApiUsageLog.create!(model: "test", agent_role: "analyst", status: "error")

    assert_includes ApiUsageLog.successful, ok
    assert_not_includes ApiUsageLog.successful, fail_log
  end

  test "failed scope filters by error status" do
    ok = ApiUsageLog.create!(model: "test", agent_role: "analyst", status: "success")
    fail_log = ApiUsageLog.create!(model: "test", agent_role: "analyst", status: "error")

    assert_includes ApiUsageLog.failed, fail_log
    assert_not_includes ApiUsageLog.failed, ok
  end

  test "total_cost_today sums estimated_cost for today" do
    ApiUsageLog.create!(model: "test", agent_role: "analyst", status: "success", estimated_cost: 0.001)
    ApiUsageLog.create!(model: "test", agent_role: "sentinel", status: "success", estimated_cost: 0.002)
    ApiUsageLog.create!(model: "test", agent_role: "analyst", status: "success", estimated_cost: 0.01, created_at: 2.days.ago)

    assert_in_delta 0.003, ApiUsageLog.total_cost_today, 0.0001
  end

  test "total_cost_today returns 0 when no records exist" do
    assert_equal 0, ApiUsageLog.total_cost_today
  end
end
