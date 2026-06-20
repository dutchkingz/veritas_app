# Admin Monitoring Dashboard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an admin-only System Command Center dashboard that surfaces real-time operational health: API costs, job success rates, database capacity, article ingestion, and system errors.

**Architecture:** New `api_usage_logs` table tracks every OpenRouter API call. A `SystemHealthService` gathers all metrics from this table plus existing DB data (Solid Queue tables, articles, ai_analyses). A single `Admin::DashboardController#show` action renders the dashboard with donut gauges, KPI cards, alerts, and detail panels. A Stimulus controller auto-refreshes every 60 seconds.

**Tech Stack:** Rails 8, PostgreSQL, Stimulus.js, inline SVG (no charting library), Solid Queue for job monitoring

---

### Task 1: Create `api_usage_logs` Migration

**Files:**
- Create: `db/migrate/TIMESTAMP_create_api_usage_logs.rb`

- [ ] **Step 1: Generate the migration**

Run:
```bash
rails generate migration CreateApiUsageLogs
```

- [ ] **Step 2: Write the migration content**

Open the generated file in `db/migrate/` and replace its content with:

```ruby
class CreateApiUsageLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :api_usage_logs do |t|
      t.string  :model,          null: false
      t.string  :agent_role,     null: false
      t.integer :input_tokens
      t.integer :output_tokens
      t.decimal :estimated_cost, precision: 10, scale: 6
      t.string  :status,         null: false
      t.string  :error_message
      t.integer :http_status
      t.timestamps
    end

    add_index :api_usage_logs, :created_at
    add_index :api_usage_logs, :status
    add_index :api_usage_logs, [:agent_role, :created_at]
  end
end
```

- [ ] **Step 3: Run the migration**

Run:
```bash
rails db:migrate
```

Expected: Migration succeeds, `api_usage_logs` table created with indexes.

- [ ] **Step 4: Verify the schema**

Run:
```bash
rails runner "puts ActiveRecord::Base.connection.columns('api_usage_logs').map(&:name).join(', ')"
```

Expected: `id, model, agent_role, input_tokens, output_tokens, estimated_cost, status, error_message, http_status, created_at, updated_at`

- [ ] **Step 5: Commit**

```bash
git add db/migrate/*_create_api_usage_logs.rb db/schema.rb
git commit -m "feat: add api_usage_logs table for tracking OpenRouter API calls"
```

---

### Task 2: Create `ApiUsageLog` Model with Tests

**Files:**
- Create: `app/models/api_usage_log.rb`
- Create: `test/models/api_usage_log_test.rb`

- [ ] **Step 1: Write the failing tests**

Create `test/models/api_usage_log_test.rb`:

```ruby
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
rails test test/models/api_usage_log_test.rb
```

Expected: FAIL — `uninitialized constant ApiUsageLog`

- [ ] **Step 3: Write the model**

Create `app/models/api_usage_log.rb`:

```ruby
class ApiUsageLog < ApplicationRecord
  scope :today, -> { where("created_at >= ?", Time.current.beginning_of_day) }
  scope :successful, -> { where(status: "success") }
  scope :failed, -> { where(status: "error") }
  scope :by_model, -> { group(:model) }

  def self.total_cost_today
    today.sum(:estimated_cost).to_f
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
rails test test/models/api_usage_log_test.rb
```

Expected: All 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add app/models/api_usage_log.rb test/models/api_usage_log_test.rb
git commit -m "feat: add ApiUsageLog model with scopes and cost aggregation"
```

---

### Task 3: Add API Usage Logging to `OpenRouterClient`

**Files:**
- Modify: `app/services/open_router_client.rb:37-59` (the `chat` method) and `:109-151` (the `request_chat` method)
- Create: `test/services/open_router_client_logging_test.rb`

The logging hook goes in the `chat` method (not `request_chat`) because `chat` has access to `agent_role` and processes the response. The `request_chat` method is recursive (retries on 402) so logging there would double-count.

- [ ] **Step 1: Write the failing test**

Create `test/services/open_router_client_logging_test.rb`:

```ruby
require "test_helper"

class OpenRouterClientLoggingTest < ActiveSupport::TestCase
  setup do
    @client = OpenRouterClient.new
  end

  test "chat logs successful API call to api_usage_logs" do
    # Stub the HTTP request to return a successful response
    success_body = {
      choices: [{ message: { content: '{"summary": "test"}' } }],
      usage: { prompt_tokens: 100, completion_tokens: 50, total_cost: 0.001 }
    }.to_json

    mock_response = Minitest::Mock.new
    mock_response.expect :is_a?, true, [Net::HTTPSuccess]
    mock_response.expect :is_a?, true, [Net::HTTPSuccess]
    mock_response.expect :body, success_body
    mock_response.expect :code, "200"

    Net::HTTP.any_instance.stubs(:request).returns(mock_response)

    assert_difference "ApiUsageLog.count", 1 do
      @client.chat(:analyst, "You are an analyst", "Analyze this")
    end

    log = ApiUsageLog.last
    assert_equal "google/gemini-2.5-flash", log.model
    assert_equal "analyst", log.agent_role
    assert_equal 100, log.input_tokens
    assert_equal 50, log.output_tokens
    assert_equal "success", log.status
    assert_equal 200, log.http_status
  end

  test "chat logs failed API call to api_usage_logs" do
    mock_response = Minitest::Mock.new
    mock_response.expect :is_a?, false, [Net::HTTPSuccess]
    mock_response.expect :code, "402"
    mock_response.expect :body, "insufficient credits"
    # request_chat checks for rate limit and credit patterns
    mock_response.expect :code, "402"
    mock_response.expect :body, "insufficient credits"
    mock_response.expect :is_a?, false, [Net::HTTPSuccess]
    mock_response.expect :code, "402"

    Net::HTTP.any_instance.stubs(:request).returns(mock_response)

    assert_difference "ApiUsageLog.count", 1 do
      assert_raises(RuntimeError) { @client.chat(:analyst, "system", "user") }
    end

    log = ApiUsageLog.last
    assert_equal "error", log.status
    assert_equal 402, log.http_status
  end

  test "logging failure does not break the API call" do
    success_body = {
      choices: [{ message: { content: '{"result": "ok"}' } }],
      usage: { prompt_tokens: 10, completion_tokens: 5, total_cost: 0.0001 }
    }.to_json

    mock_response = Minitest::Mock.new
    mock_response.expect :is_a?, true, [Net::HTTPSuccess]
    mock_response.expect :is_a?, true, [Net::HTTPSuccess]
    mock_response.expect :body, success_body
    mock_response.expect :code, "200"

    Net::HTTP.any_instance.stubs(:request).returns(mock_response)
    ApiUsageLog.stubs(:create!).raises(ActiveRecord::ActiveRecordError, "DB down")

    # Should not raise despite logging failure
    result = @client.chat(:analyst, "system", "user")
    assert_equal({ "result" => "ok" }, result)
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
rails test test/services/open_router_client_logging_test.rb
```

Expected: FAIL — logging doesn't happen yet, so `ApiUsageLog.count` doesn't change.

- [ ] **Step 3: Modify the `chat` method to log API calls**

In `app/services/open_router_client.rb`, replace the `chat` method (lines 37-59) with:

```ruby
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
    log_api_usage(
      model: model,
      agent_role: agent_role,
      response: response,
      data: data
    )

    content = data.dig("choices", 0, "message", "content")

    if expect_json
      # Strip markdown code fences if the model wraps JSON in ```json blocks
      cleaned = content.gsub(/\A```json\s*/i, '').gsub(/```\s*\z/, '').strip
      JSON.parse(cleaned)
    else
      content
    end
  end
```

Then modify `request_chat` (line 134) so that on error it returns the response instead of raising immediately. Actually, `request_chat` raises on error, so we need to catch errors in `chat` to log them. Replace the `chat` method with a version that rescues:

```ruby
  def chat(agent_role, system_prompt, user_prompt, expect_json: true)
    model      = resolve_model(agent_role)
    max_tokens = MAX_TOKENS.fetch(agent_role.to_sym, 700)

    begin
      response = request_chat(
        model: model,
        system_prompt: system_prompt,
        user_prompt: user_prompt,
        expect_json: expect_json,
        max_tokens: max_tokens
      )

      data = JSON.parse(response.body)
      log_api_usage(model: model, agent_role: agent_role, response: response, data: data)

      content = data.dig("choices", 0, "message", "content")

      if expect_json
        cleaned = content.gsub(/\A```json\s*/i, '').gsub(/```\s*\z/, '').strip
        JSON.parse(cleaned)
      else
        content
      end
    rescue => e
      log_api_usage_error(model: model, agent_role: agent_role, error: e)
      raise
    end
  end
```

Add these private methods at the bottom of the class (before the final `end`):

```ruby
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
rails test test/services/open_router_client_logging_test.rb
```

Expected: All 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add app/services/open_router_client.rb test/services/open_router_client_logging_test.rb
git commit -m "feat: log every OpenRouter API call to api_usage_logs"
```

---

### Task 4: Create `SystemHealthService` with Tests

**Files:**
- Create: `app/services/system_health_service.rb`
- Create: `test/services/system_health_service_test.rb`

- [ ] **Step 1: Write the failing tests**

Create `test/services/system_health_service_test.rb`:

```ruby
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
rails test test/services/system_health_service_test.rb
```

Expected: FAIL — `uninitialized constant SystemHealthService`

- [ ] **Step 3: Write the service**

Create `app/services/system_health_service.rb`:

```ruby
class SystemHealthService
  DB_LIMIT_BYTES = 500.megabytes # Neon free tier
  DATA_TRANSFER_LIMIT_GB = 5.0  # Neon free tier monthly

  def call
    {
      gauges: build_gauges,
      kpis: build_kpis,
      alerts: build_alerts,
      recent_errors: build_recent_errors,
      api_breakdown: build_api_breakdown,
      db_stats: build_db_stats,
      ingestion: build_ingestion_stats
    }
  end

  private

  def build_gauges
    db_size = db_size_bytes

    {
      db_storage: {
        used_bytes: db_size,
        limit_bytes: DB_LIMIT_BYTES,
        percentage: (db_size.to_f / DB_LIMIT_BYTES * 100).round(1)
      },
      api_credits: {
        spent_today: ApiUsageLog.total_cost_today,
        spent_month: ApiUsageLog.where("created_at >= ?", Time.current.beginning_of_month).sum(:estimated_cost).to_f
      },
      data_transfer: {
        limit_gb: DATA_TRANSFER_LIMIT_GB
      }
    }
  end

  def build_kpis
    today_logs = ApiUsageLog.today
    articles_today = Article.where("fetched_at >= ?", Time.current.beginning_of_day).count
    analyzed_today = AiAnalysis.where("created_at >= ?", Time.current.beginning_of_day).count
    pending = Article.left_joins(:ai_analysis).where(ai_analyses: { id: nil }).count

    job_stats = job_success_stats

    {
      api_spend_today: today_logs.sum(:estimated_cost).to_f,
      api_spend_month: ApiUsageLog.where("created_at >= ?", Time.current.beginning_of_month).sum(:estimated_cost).to_f,
      job_success_rate: job_stats[:rate],
      job_succeeded: job_stats[:succeeded],
      job_total: job_stats[:total],
      db_size_bytes: db_size_bytes,
      db_percentage: (db_size_bytes.to_f / DB_LIMIT_BYTES * 100).round(1),
      articles_today: articles_today,
      articles_analyzed: analyzed_today,
      articles_pending: pending
    }
  end

  def build_alerts
    alerts = []
    kpis = build_kpis
    db_pct = kpis[:db_percentage]

    # DB size alerts
    if db_pct > 80
      alerts << { level: :red, message: "Database storage at #{db_pct}% of 500 MB limit" }
    elsif db_pct > 60
      alerts << { level: :amber, message: "Database storage at #{db_pct}% of 500 MB limit" }
    end

    # Job failure rate
    if kpis[:job_total] > 0 && kpis[:job_success_rate] < 50
      alerts << { level: :red, message: "Job success rate #{kpis[:job_success_rate]}% — #{kpis[:job_succeeded]}/#{kpis[:job_total]} in last 24h" }
    end

    # No articles fetched recently
    last_fetch = Article.maximum(:fetched_at)
    if last_fetch && last_fetch < 2.hours.ago
      alerts << { level: :amber, message: "No articles fetched in last 2 hours (last: #{time_ago_in_words(last_fetch)})" }
    end

    # API errors in last hour
    recent_errors = ApiUsageLog.failed.where("created_at >= ?", 1.hour.ago).count
    if recent_errors > 10
      alerts << { level: :red, message: "#{recent_errors} API errors in the last hour" }
    end

    alerts << { level: :green, message: "Systems nominal" } if alerts.empty?

    alerts
  end

  def build_recent_errors
    api_errors = ApiUsageLog.failed.order(created_at: :desc).limit(10).map do |log|
      {
        source: "API",
        label: "#{log.agent_role} → #{log.model}",
        message: log.error_message.to_s.truncate(100),
        http_status: log.http_status,
        timestamp: log.created_at
      }
    end

    job_errors = SolidQueue::FailedExecution.order(created_at: :desc).limit(10).map do |fe|
      {
        source: "Job",
        label: fe.job&.class_name || "Unknown",
        message: fe.error.to_s.truncate(100),
        http_status: nil,
        timestamp: fe.created_at
      }
    end

    (api_errors + job_errors).sort_by { |e| e[:timestamp] }.reverse.first(20)
  end

  def build_api_breakdown
    ApiUsageLog.today.group(:model).select(
      "model",
      "COUNT(*) as call_count",
      "SUM(estimated_cost) as total_cost",
      "SUM(input_tokens) as total_input_tokens",
      "SUM(output_tokens) as total_output_tokens"
    ).order("total_cost DESC NULLS LAST").map do |row|
      {
        model: row.model,
        call_count: row.call_count,
        total_cost: row.total_cost.to_f,
        total_input_tokens: row.total_input_tokens.to_i,
        total_output_tokens: row.total_output_tokens.to_i
      }
    end
  end

  def build_db_stats
    tables = ActiveRecord::Base.connection.execute(<<~SQL).to_a
      SELECT relname AS table_name,
             n_live_tup AS row_count,
             pg_total_relation_size(quote_ident(relname)) AS size_bytes
      FROM pg_stat_user_tables
      ORDER BY pg_total_relation_size(quote_ident(relname)) DESC
      LIMIT 10
    SQL

    {
      total_size_bytes: db_size_bytes,
      total_size_pretty: pretty_bytes(db_size_bytes),
      tables: tables.map do |t|
        {
          name: t["table_name"],
          row_count: t["row_count"].to_i,
          size_bytes: t["size_bytes"].to_i,
          size_pretty: pretty_bytes(t["size_bytes"].to_i)
        }
      end
    }
  end

  def build_ingestion_stats
    {
      last_fetch: Article.maximum(:fetched_at),
      articles_today: Article.where("fetched_at >= ?", Time.current.beginning_of_day).count,
      articles_analyzed: AiAnalysis.where("created_at >= ?", Time.current.beginning_of_day).count,
      articles_pending: Article.left_joins(:ai_analysis).where(ai_analyses: { id: nil }).count,
      sources: active_sources
    }
  end

  # --- helpers ---

  def db_size_bytes
    @db_size_bytes ||= ActiveRecord::Base.connection
      .select_value("SELECT pg_database_size(current_database())").to_i
  end

  def job_success_stats
    since = 24.hours.ago
    total = SolidQueue::Job.where("created_at >= ?", since).count
    failed = SolidQueue::FailedExecution.where("created_at >= ?", since).count
    succeeded = total - failed
    rate = total > 0 ? (succeeded.to_f / total * 100).round(1) : 100.0

    { succeeded: succeeded, total: total, rate: rate }
  end

  def active_sources
    sources = []
    sources << "NewsAPI" if Article.where("source_api = 'newsapi' OR source_api IS NULL").exists?
    sources << "GDELT" if Article.where(source_api: "gdelt").exists?
    sources
  end

  def pretty_bytes(bytes)
    if bytes >= 1.gigabyte
      "#{(bytes.to_f / 1.gigabyte).round(2)} GB"
    elsif bytes >= 1.megabyte
      "#{(bytes.to_f / 1.megabyte).round(1)} MB"
    elsif bytes >= 1.kilobyte
      "#{(bytes.to_f / 1.kilobyte).round(1)} KB"
    else
      "#{bytes} B"
    end
  end

  def time_ago_in_words(time)
    seconds = (Time.current - time).to_i
    case seconds
    when 0..59 then "#{seconds}s ago"
    when 60..3599 then "#{seconds / 60}m ago"
    when 3600..86399 then "#{seconds / 3600}h ago"
    else "#{seconds / 86400}d ago"
    end
  end
end
```

- [ ] **Step 4: Run the tests**

Run:
```bash
rails test test/services/system_health_service_test.rb
```

Expected: All 9 tests pass.

- [ ] **Step 5: Commit**

```bash
git add app/services/system_health_service.rb test/services/system_health_service_test.rb
git commit -m "feat: add SystemHealthService to gather all dashboard metrics"
```

---

### Task 5: Create `Admin::DashboardController` with Tests

**Files:**
- Create: `app/controllers/admin/dashboard_controller.rb`
- Create: `test/controllers/admin/dashboard_controller_test.rb`

- [ ] **Step 1: Write the failing test**

Create `test/controllers/admin/dashboard_controller_test.rb`:

```ruby
require "test_helper"

class Admin::DashboardControllerTest < ActionDispatch::IntegrationTest
  test "show returns forbidden for non-admin users" do
    user = users(:default)  # non-admin user fixture
    sign_in user
    get admin_dashboard_path
    assert_response :redirect  # redirects with "Access Denied"
  end

  test "show returns forbidden for unauthenticated users" do
    get admin_dashboard_path
    assert_response :redirect
  end

  test "show renders successfully for admin users" do
    admin = users(:admin)  # admin user fixture
    sign_in admin
    get admin_dashboard_path
    assert_response :success
    assert_select "title", /Command Center/i  # or check for a known element
  end
end
```

**Note:** These tests depend on user fixtures. If the project uses fixtures, ensure there is an `:admin` fixture with `role: admin` and a `:default` fixture with `role: user` in `test/fixtures/users.yml`. If Devise `sign_in` helper is not already configured for integration tests, add `include Devise::Test::IntegrationHelpers` to `test/test_helper.rb`.

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
rails test test/controllers/admin/dashboard_controller_test.rb
```

Expected: FAIL — controller doesn't exist yet.

- [ ] **Step 3: Create the controller**

Create `app/controllers/admin/dashboard_controller.rb`:

```ruby
class Admin::DashboardController < ApplicationController
  before_action :ensure_admin!

  def show
    @health = SystemHealthService.new.call
  end

  private

  def ensure_admin!
    return if current_user&.admin?

    respond_to do |format|
      format.html { redirect_to root_path, alert: "Access Denied." }
      format.json { render json: { error: "Admin access required" }, status: :forbidden }
    end
  end
end
```

- [ ] **Step 4: Add the route**

In `config/routes.rb`, inside the `namespace :admin do` block (after line 72), add:

```ruby
    get "dashboard", to: "dashboard#show"
```

- [ ] **Step 5: Create a minimal placeholder view**

Create `app/views/admin/dashboard/show.html.erb` with a placeholder:

```erb
<div>
  <h1>Command Center</h1>
  <p>Dashboard loading...</p>
</div>
```

- [ ] **Step 6: Run the controller tests**

Run:
```bash
rails test test/controllers/admin/dashboard_controller_test.rb
```

Expected: Tests pass (may need fixture adjustments — see note in Step 1).

- [ ] **Step 7: Commit**

```bash
git add app/controllers/admin/dashboard_controller.rb test/controllers/admin/dashboard_controller_test.rb config/routes.rb app/views/admin/dashboard/show.html.erb
git commit -m "feat: add admin dashboard controller with auth and route"
```

---

### Task 6: Build the Dashboard View

**Files:**
- Modify: `app/views/admin/dashboard/show.html.erb` (replace placeholder)

This is the largest task — the full cyberpunk dashboard view. No test for this one; verify visually by loading `http://localhost:3000/admin/dashboard` as an admin user.

- [ ] **Step 1: Replace the placeholder view with the full dashboard**

Replace the content of `app/views/admin/dashboard/show.html.erb` with:

```erb
<% content_for :title, "VERITAS — System Command Center" %>

<div class="veritas-container py-4 px-4" style="background-color: #0a0e1a; min-height: 100vh; color: #f8fafc; font-family: 'Space Grotesk', sans-serif;"
     data-controller="auto-refresh">

  <%# --- Header --- %>
  <div class="d-flex justify-content-between align-items-center mb-4">
    <h1 style="font-family: 'JetBrains Mono', monospace; font-size: 1rem; letter-spacing: 0.2em; color: #00f0ff; text-transform: uppercase;">
      <span class="me-2">&#x26A8;</span> System Command Center
    </h1>
    <span style="font-family: 'JetBrains Mono', monospace; font-size: 0.65rem; color: #475569;">
      Auto-refresh: 60s &bull; <%= Time.current.strftime("%Y-%m-%d %H:%M:%S UTC") %>
    </span>
  </div>

  <%# --- Row 1: Donut Gauges --- %>
  <div class="d-flex justify-content-center gap-4 mb-4">
    <%= render partial: "admin/dashboard/donut_gauge", locals: {
      label: "DB STORAGE",
      percentage: @health[:gauges][:db_storage][:percentage],
      subtitle: "#{number_to_human_size(@health[:gauges][:db_storage][:used_bytes])} / 500 MB"
    } %>
    <%= render partial: "admin/dashboard/donut_gauge", locals: {
      label: "API SPEND",
      percentage: [(@health[:kpis][:api_spend_month] / 5.0 * 100), 100].min.round(1),
      subtitle: "$#{'%.2f' % @health[:kpis][:api_spend_month]} / $5.00"
    } %>
    <%= render partial: "admin/dashboard/donut_gauge", locals: {
      label: "DATA TRANSFER",
      percentage: 0,
      subtitle: "Estimated (check Neon)"
    } %>
  </div>

  <%# --- Row 2: KPI Cards --- %>
  <div style="display: grid; grid-template-columns: repeat(5, 1fr); gap: 12px; margin-bottom: 20px;">
    <%# API Spend Today %>
    <div style="background: #1e293b; border: 1px solid #334155; border-radius: 6px; padding: 14px; text-align: center;">
      <div style="font-size: 0.6rem; color: #64748b; text-transform: uppercase; letter-spacing: 1px; font-family: 'JetBrains Mono', monospace;">API Spend Today</div>
      <div style="font-size: 1.4rem; font-weight: bold; color: #00f0ff; margin: 6px 0; font-family: 'JetBrains Mono', monospace;">$<%= "%.4f" % @health[:kpis][:api_spend_today] %></div>
      <div style="font-size: 0.6rem; color: #64748b; font-family: 'JetBrains Mono', monospace;">$<%= "%.2f" % @health[:kpis][:api_spend_month] %> this month</div>
    </div>

    <%# Job Success Rate %>
    <% job_color = @health[:kpis][:job_success_rate] >= 80 ? "#22c55e" : @health[:kpis][:job_success_rate] >= 50 ? "#f59e0b" : "#ef4444" %>
    <div style="background: #1e293b; border: 1px solid #334155; border-radius: 6px; padding: 14px; text-align: center;">
      <div style="font-size: 0.6rem; color: #64748b; text-transform: uppercase; letter-spacing: 1px; font-family: 'JetBrains Mono', monospace;">Job Success</div>
      <div style="font-size: 1.4rem; font-weight: bold; color: <%= job_color %>; margin: 6px 0; font-family: 'JetBrains Mono', monospace;"><%= @health[:kpis][:job_success_rate] %>%</div>
      <div style="font-size: 0.6rem; color: #64748b; font-family: 'JetBrains Mono', monospace;"><%= @health[:kpis][:job_succeeded] %>/<%= @health[:kpis][:job_total] %> succeeded</div>
    </div>

    <%# DB Size %>
    <% db_color = @health[:kpis][:db_percentage] > 80 ? "#ef4444" : @health[:kpis][:db_percentage] > 60 ? "#f59e0b" : "#22c55e" %>
    <div style="background: #1e293b; border: 1px solid #334155; border-radius: 6px; padding: 14px; text-align: center;">
      <div style="font-size: 0.6rem; color: #64748b; text-transform: uppercase; letter-spacing: 1px; font-family: 'JetBrains Mono', monospace;">DB Size</div>
      <div style="font-size: 1.4rem; font-weight: bold; color: <%= db_color %>; margin: 6px 0; font-family: 'JetBrains Mono', monospace;"><%= number_to_human_size(@health[:kpis][:db_size_bytes]) %></div>
      <div style="font-size: 0.6rem; color: #64748b; font-family: 'JetBrains Mono', monospace;"><%= @health[:kpis][:db_percentage] %>% of 500 MB</div>
    </div>

    <%# Articles Today %>
    <div style="background: #1e293b; border: 1px solid #334155; border-radius: 6px; padding: 14px; text-align: center;">
      <div style="font-size: 0.6rem; color: #64748b; text-transform: uppercase; letter-spacing: 1px; font-family: 'JetBrains Mono', monospace;">Articles Today</div>
      <div style="font-size: 1.4rem; font-weight: bold; color: #22c55e; margin: 6px 0; font-family: 'JetBrains Mono', monospace;"><%= @health[:kpis][:articles_today] %></div>
      <div style="font-size: 0.6rem; color: #64748b; font-family: 'JetBrains Mono', monospace;"><%= @health[:kpis][:articles_analyzed] %> analyzed, <%= @health[:kpis][:articles_pending] %> pending</div>
    </div>

    <%# Queue Depth %>
    <div style="background: #1e293b; border: 1px solid #334155; border-radius: 6px; padding: 14px; text-align: center;">
      <div style="font-size: 0.6rem; color: #64748b; text-transform: uppercase; letter-spacing: 1px; font-family: 'JetBrains Mono', monospace;">Queue Depth</div>
      <div style="font-size: 1.4rem; font-weight: bold; color: #00f0ff; margin: 6px 0; font-family: 'JetBrains Mono', monospace;"><%= SolidQueue::Job.where(finished_at: nil).count %></div>
      <div style="font-size: 0.6rem; color: #64748b; font-family: 'JetBrains Mono', monospace;">jobs queued</div>
    </div>
  </div>

  <%# --- Row 3: Two-Column Detail Area --- %>
  <div style="display: grid; grid-template-columns: 3fr 2fr; gap: 16px;">

    <%# --- Left Column: Alerts + Errors --- %>
    <div>
      <%# Active Alerts %>
      <% worst_level = @health[:alerts].map { |a| a[:level] }.min_by { |l| { red: 0, amber: 1, green: 2 }[l] } %>
      <% border_color = { red: "#ef4444", amber: "#f59e0b", green: "#22c55e" }[worst_level] %>
      <div style="background: #1e293b; border: 1px solid <%= border_color %>66; border-radius: 6px; padding: 16px; margin-bottom: 16px;">
        <div style="font-size: 0.7rem; color: <%= border_color %>; font-weight: bold; margin-bottom: 12px; text-transform: uppercase; letter-spacing: 1px; font-family: 'JetBrains Mono', monospace;">
          &#9888; Active Alerts
        </div>
        <% @health[:alerts].each do |alert| %>
          <% color = { red: "#ef4444", amber: "#f59e0b", green: "#22c55e" }[alert[:level]] %>
          <div style="font-size: 0.7rem; color: <%= color %>; margin-bottom: 8px; padding: 8px; background: <%= color %>11; border-radius: 4px; font-family: 'JetBrains Mono', monospace;">
            &#x25CF; <%= alert[:message] %>
          </div>
        <% end %>
      </div>

      <%# Recent Errors %>
      <div style="background: #1e293b; border: 1px solid #334155; border-radius: 6px; padding: 16px;">
        <div style="font-size: 0.7rem; color: #00f0ff; font-weight: bold; margin-bottom: 12px; text-transform: uppercase; letter-spacing: 1px; font-family: 'JetBrains Mono', monospace;">
          Recent Errors
        </div>
        <% if @health[:recent_errors].any? %>
          <% @health[:recent_errors].each do |error| %>
            <div style="padding: 6px 0; border-bottom: 1px solid #334155; display: flex; justify-content: space-between; align-items: center; gap: 8px; font-family: 'JetBrains Mono', monospace; font-size: 0.65rem;">
              <span style="color: #ef4444; white-space: nowrap;"><%= error[:source] %>: <%= error[:label] %></span>
              <span style="color: #64748b; flex: 1; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;"><%= error[:http_status] ? "#{error[:http_status]} — " : "" %><%= error[:message] %></span>
              <span style="color: #475569; white-space: nowrap;"><%= time_ago_in_words(error[:timestamp]) %> ago</span>
            </div>
          <% end %>
        <% else %>
          <div style="font-size: 0.7rem; color: #22c55e; font-family: 'JetBrains Mono', monospace;">No recent errors</div>
        <% end %>
      </div>
    </div>

    <%# --- Right Column: API + DB + Ingestion --- %>
    <div>
      <%# API Usage by Model %>
      <div style="background: #1e293b; border: 1px solid #334155; border-radius: 6px; padding: 16px; margin-bottom: 16px;">
        <div style="font-size: 0.7rem; color: #00f0ff; font-weight: bold; margin-bottom: 12px; text-transform: uppercase; letter-spacing: 1px; font-family: 'JetBrains Mono', monospace;">
          API Usage by Model
        </div>
        <% if @health[:api_breakdown].any? %>
          <% @health[:api_breakdown].each do |row| %>
            <div style="display: flex; justify-content: space-between; padding: 4px 0; font-family: 'JetBrains Mono', monospace; font-size: 0.65rem; color: #94a3b8;">
              <span><%= row[:model] %></span>
              <span><%= row[:call_count] %> calls</span>
              <span style="color: #00f0ff;">$<%= "%.4f" % row[:total_cost] %></span>
            </div>
          <% end %>
        <% else %>
          <div style="font-size: 0.65rem; color: #475569; font-family: 'JetBrains Mono', monospace;">No API calls today</div>
        <% end %>
      </div>

      <%# Database Stats %>
      <div style="background: #1e293b; border: 1px solid #334155; border-radius: 6px; padding: 16px; margin-bottom: 16px;">
        <div style="font-size: 0.7rem; color: #00f0ff; font-weight: bold; margin-bottom: 12px; text-transform: uppercase; letter-spacing: 1px; font-family: 'JetBrains Mono', monospace;">
          Database
        </div>
        <% @health[:db_stats][:tables].first(5).each do |table| %>
          <div style="display: flex; justify-content: space-between; padding: 4px 0; font-family: 'JetBrains Mono', monospace; font-size: 0.65rem; color: #94a3b8;">
            <span><%= table[:name] %></span>
            <span><%= number_with_delimiter(table[:row_count]) %> rows</span>
            <span><%= table[:size_pretty] %></span>
          </div>
        <% end %>
        <%# Capacity bar %>
        <div style="margin-top: 10px;">
          <div style="height: 6px; background: #0f172a; border-radius: 3px; overflow: hidden;">
            <div style="width: <%= @health[:gauges][:db_storage][:percentage] %>%; height: 100%; background: linear-gradient(90deg, #00f0ff, #f59e0b); border-radius: 3px;"></div>
          </div>
          <div style="font-size: 0.6rem; color: #64748b; margin-top: 4px; font-family: 'JetBrains Mono', monospace;">
            <%= @health[:db_stats][:total_size_pretty] %> / 500 MB (<%= @health[:gauges][:db_storage][:percentage] %>%)
          </div>
        </div>
      </div>

      <%# Ingestion Pipeline %>
      <div style="background: #1e293b; border: 1px solid #334155; border-radius: 6px; padding: 16px;">
        <div style="font-size: 0.7rem; color: #00f0ff; font-weight: bold; margin-bottom: 12px; text-transform: uppercase; letter-spacing: 1px; font-family: 'JetBrains Mono', monospace;">
          Ingestion Pipeline
        </div>
        <% ingestion = @health[:ingestion] %>
        <div style="font-family: 'JetBrains Mono', monospace; font-size: 0.65rem; color: #94a3b8;">
          <div style="display: flex; justify-content: space-between; padding: 4px 0;">
            <span>Last fetch</span>
            <% if ingestion[:last_fetch] %>
              <span style="color: <%= ingestion[:last_fetch] > 2.hours.ago ? '#22c55e' : '#f59e0b' %>;"><%= time_ago_in_words(ingestion[:last_fetch]) %> ago</span>
            <% else %>
              <span style="color: #ef4444;">Never</span>
            <% end %>
          </div>
          <div style="display: flex; justify-content: space-between; padding: 4px 0;">
            <span>Fetched today</span>
            <span><%= ingestion[:articles_today] %> articles</span>
          </div>
          <div style="display: flex; justify-content: space-between; padding: 4px 0;">
            <span>Analyzed</span>
            <span style="color: #22c55e;"><%= ingestion[:articles_analyzed] %></span>
          </div>
          <div style="display: flex; justify-content: space-between; padding: 4px 0;">
            <span>Pending analysis</span>
            <span style="color: <%= ingestion[:articles_pending] > 0 ? '#f59e0b' : '#22c55e' %>;"><%= ingestion[:articles_pending] %></span>
          </div>
          <div style="display: flex; justify-content: space-between; padding: 4px 0;">
            <span>Sources active</span>
            <span><%= ingestion[:sources].join(", ") %></span>
          </div>
        </div>
      </div>
    </div>
  </div>
</div>
```

- [ ] **Step 2: Create the donut gauge partial**

Create `app/views/admin/dashboard/_donut_gauge.html.erb`:

```erb
<%
  color = if percentage > 80
    "#ef4444"
  elsif percentage > 60
    "#f59e0b"
  else
    "#22c55e"
  end
  dash = [percentage, 100].min
  gap = 100 - dash
%>
<div style="text-align: center;">
  <div style="position: relative; width: 100px; height: 100px; margin: 0 auto;">
    <svg viewBox="0 0 36 36" style="transform: rotate(-90deg);">
      <circle cx="18" cy="18" r="14" fill="none" stroke="#1e293b" stroke-width="3"/>
      <circle cx="18" cy="18" r="14" fill="none" stroke="<%= color %>" stroke-width="3" stroke-dasharray="<%= dash %> <%= gap %>" stroke-linecap="round"/>
    </svg>
    <div style="position: absolute; top: 50%; left: 50%; transform: translate(-50%, -50%); color: <%= color %>; font-family: 'JetBrains Mono', monospace; font-size: 14px; font-weight: bold;">
      <%= percentage.round(0) %>%
    </div>
  </div>
  <div style="font-family: 'JetBrains Mono', monospace; font-size: 0.6rem; color: #94a3b8; margin-top: 6px; text-transform: uppercase; letter-spacing: 1px;"><%= label %></div>
  <div style="font-family: 'JetBrains Mono', monospace; font-size: 0.55rem; color: #64748b;"><%= subtitle %></div>
</div>
```

- [ ] **Step 3: Start the dev server and verify the page loads**

Run:
```bash
rails s
```

Navigate to `http://localhost:3000/admin/dashboard` as an admin user. Verify:
- Donut gauges render with correct colors
- KPI cards show real data
- Alerts section appears
- Recent errors list populated (or "No recent errors")
- API breakdown table shows data
- Database stats show table sizes
- Ingestion pipeline shows last fetch time

- [ ] **Step 4: Commit**

```bash
git add app/views/admin/dashboard/show.html.erb app/views/admin/dashboard/_donut_gauge.html.erb
git commit -m "feat: build full admin dashboard view with donut gauges, KPIs, alerts, and detail panels"
```

---

### Task 7: Create Auto-Refresh Stimulus Controller

**Files:**
- Create: `app/javascript/controllers/auto_refresh_controller.js`

- [ ] **Step 1: Create the Stimulus controller**

Create `app/javascript/controllers/auto_refresh_controller.js`:

```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.interval = setInterval(() => {
      Turbo.visit(window.location.href, { action: "replace" })
    }, 60000)
  }

  disconnect() {
    clearInterval(this.interval)
  }
}
```

- [ ] **Step 2: Verify auto-registration**

Stimulus controllers in `app/javascript/controllers/` are auto-registered by the Rails Stimulus loader. The view already has `data-controller="auto-refresh"` on the container div. No manual registration needed.

- [ ] **Step 3: Verify in browser**

Load the dashboard, wait 60 seconds. The page should silently refresh without a full navigation (Turbo replaces the body). Check the browser console for no errors.

- [ ] **Step 4: Commit**

```bash
git add app/javascript/controllers/auto_refresh_controller.js
git commit -m "feat: add auto-refresh Stimulus controller for 60s dashboard polling"
```

---

### Task 8: Add Recurring Cleanup Job

**Files:**
- Modify: `config/recurring.yml`

- [ ] **Step 1: Add the prune job to the production section**

In `config/recurring.yml`, add this entry at the end of the `production:` section (before the `development:` section):

```yaml
  prune_api_usage_logs:
    command: "ApiUsageLog.where('created_at < ?', 30.days.ago).delete_all"
    schedule: every day at 3am
```

- [ ] **Step 2: Add the same entry to the `development:` section**

Add the same entry at the end of the `development:` section:

```yaml
  prune_api_usage_logs:
    command: "ApiUsageLog.where('created_at < ?', 30.days.ago).delete_all"
    schedule: every day at 3am
```

- [ ] **Step 3: Commit**

```bash
git add config/recurring.yml
git commit -m "feat: add daily prune job for api_usage_logs older than 30 days"
```

---

### Task 9: Add Navigation Link to Dashboard

**Files:**
- Modify: `app/views/admin/users/index.html.erb` (or the admin layout/nav partial)

- [ ] **Step 1: Find where admin navigation links are rendered**

Check if there's a shared admin layout or nav partial:
```bash
grep -r "admin" app/views/layouts/ --include="*.erb" -l
ls app/views/shared/ 2>/dev/null
```

If admin nav links are in the users index or a shared partial, add a "Command Center" link.

- [ ] **Step 2: Add the navigation link**

Add a link to the dashboard near other admin navigation. The exact location depends on the layout structure. The link should be:

```erb
<%= link_to admin_dashboard_path, style: "font-family: 'JetBrains Mono', monospace; font-size: 0.7rem; letter-spacing: 0.1em; color: #00f0ff; text-decoration: none; text-transform: uppercase;" do %>
  &#x26A8; Command Center
<% end %>
```

Place it where admin users will see it — either in a shared nav bar or at the top of the admin users page.

- [ ] **Step 3: Verify the link works**

Navigate to the admin area and click the "Command Center" link. It should load the dashboard.

- [ ] **Step 4: Commit**

```bash
git add app/views/
git commit -m "feat: add Command Center navigation link for admin users"
```

---

### Task 10: Final Integration Verification

- [ ] **Step 1: Run the full test suite for new files**

```bash
rails test test/models/api_usage_log_test.rb test/services/system_health_service_test.rb test/services/open_router_client_logging_test.rb test/controllers/admin/dashboard_controller_test.rb
```

Expected: All tests pass.

- [ ] **Step 2: Verify the dashboard end-to-end in the browser**

As an admin user, navigate to `/admin/dashboard` and check:
1. Three donut gauges render (DB Storage, API Spend, Data Transfer)
2. Five KPI cards show real data
3. Alerts section shows "Systems nominal" or real alerts
4. Recent errors section is populated or shows "No recent errors"
5. API Usage by Model shows breakdown (will be empty until API calls are made)
6. Database section shows table sizes with capacity bar
7. Ingestion Pipeline shows last fetch, counts, and sources
8. Page auto-refreshes after 60 seconds

- [ ] **Step 3: Trigger an API call and verify logging**

Run in Rails console:
```ruby
client = OpenRouterClient.new
client.chat(:analyst, "You are a test", "Say hello", expect_json: false)
ApiUsageLog.last
```

Verify the log entry has model, agent_role, token counts, cost, and status "success".

- [ ] **Step 4: Reload dashboard and verify API breakdown updates**

Refresh `/admin/dashboard` — the API Usage by Model section should now show the call you just made.

- [ ] **Step 5: Verify non-admin access is blocked**

Log in as a non-admin user and navigate to `/admin/dashboard`. Should redirect with "Access Denied."

- [ ] **Step 6: Final commit if any cleanup was needed**

```bash
git add -A
git commit -m "chore: final integration cleanup for admin monitoring dashboard"
```
