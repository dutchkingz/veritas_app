# VERITAS System Command Center — Design Spec

## Overview

An admin-only monitoring dashboard that provides real-time visibility into VERITAS operational health: API costs, job success rates, database capacity, article ingestion, and system errors.

**Route:** `GET /admin/dashboard`
**Access:** Admin users only (existing `admin?` role check via Pundit)
**Auto-refresh:** 60-second poll via Stimulus controller

## Problem Statement

VERITAS has multiple external dependencies (OpenRouter API, Neon database, NewsAPI) with hard usage limits. Without monitoring, failures cascade silently — retired models cause 100% job failure rates, API credits drain unnoticed, and database transfer quotas exhaust within hours. This dashboard surfaces those problems immediately.

## Data Layer

### New Table: `api_usage_logs`

Tracks each OpenRouter API call for cost and error visibility.

```ruby
create_table :api_usage_logs do |t|
  t.string  :model,          null: false  # e.g. "google/gemini-2.5-flash"
  t.string  :agent_role,     null: false  # e.g. "analyst", "sentinel", "arbiter"
  t.integer :input_tokens
  t.integer :output_tokens
  t.decimal :estimated_cost, precision: 10, scale: 6
  t.string  :status,         null: false  # "success" or "error"
  t.string  :error_message                # null on success, error text on failure
  t.integer :http_status                  # HTTP response code
  t.timestamps
end

add_index :api_usage_logs, :created_at
add_index :api_usage_logs, :status
add_index :api_usage_logs, [:agent_role, :created_at]
```

**Retention:** Rows older than 30 days are pruned by a recurring job to keep the table small.

### Logging Hook

Add logging to `OpenRouterClient#request_chat`. After every API call (success or failure), insert one row into `api_usage_logs`. Extract token counts from the response `usage` field when available.

```ruby
# In OpenRouterClient#request_chat, after receiving the response:
ApiUsageLog.create!(
  model: model,
  agent_role: agent_role.to_s,
  input_tokens: data.dig("usage", "prompt_tokens"),
  output_tokens: data.dig("usage", "completion_tokens"),
  estimated_cost: data.dig("usage", "total_cost"),  # OpenRouter provides this
  status: response.is_a?(Net::HTTPSuccess) ? "success" : "error",
  error_message: response.is_a?(Net::HTTPSuccess) ? nil : response.body.truncate(500),
  http_status: response.code.to_i
)
```

### Computed Metrics (no new tables)

These are queried from existing data at page load:

- **DB size:** `SELECT pg_size_pretty(pg_database_size(current_database()))`
- **Table sizes:** `pg_total_relation_size()` per table
- **Article counts:** `Article.where("fetched_at >= ?", Time.current.beginning_of_day).count`
- **Articles analyzed:** `AiAnalysis.where("created_at >= ?", Time.current.beginning_of_day).count`
- **Articles pending:** Articles without ai_analysis
- **Job success/failure:** Query `solid_queue_jobs` for recent completions and failures
- **Last fetch time:** Most recent `FetchArticlesJob` completion
- **Queue depth:** `SolidQueue::Job.where(finished_at: nil).count`

## Page Layout

### Row 1: Donut Gauges (Bounded Capacity Metrics)

Three SVG donut rings showing usage against hard limits. Color shifts:
- **Green** (0-60%): healthy
- **Amber** (60-80%): warning
- **Red** (80-100%): critical

| Gauge | Source | Limit |
|-------|--------|-------|
| DB Storage | `pg_database_size()` | 500 MB (Neon free tier) |
| API Credits | OpenRouter balance (cached, fetched via API or manual config) | User-configured budget |
| Data Transfer | Estimated from `api_usage_logs` row count × avg query size | 5 GB/month (Neon free tier) |

**Note on Data Transfer:** Neon does not expose transfer usage via API. We estimate it by tracking query volume in `api_usage_logs` and article ingestion counts. The admin can also manually update a `neon_transfer_used_gb` setting if they check the Neon dashboard.

### Row 2: KPI Cards

Five cards with headline number, label, and subtitle:

| Card | Value | Subtitle |
|------|-------|----------|
| API Spend Today | Sum of `estimated_cost` from `api_usage_logs` today | Monthly total |
| Credits Remaining | Last known balance | Warning if < $1 |
| Job Success Rate | Successful / total jobs in last 24h | X/Y succeeded |
| DB Size | Total database size | % of 500 MB limit |
| Articles Today | Articles fetched today | X analyzed, Y pending |

### Row 3: Two-Column Detail Area

**Left Column (60% width):**

1. **Active Alerts** — Auto-generated from threshold checks:
   - API credits < $1.00 → red alert
   - DB size > 80% of 500 MB → amber alert
   - Job failure rate > 50% in last hour → red alert
   - Data transfer > 80% of 5 GB → amber alert
   - No articles fetched in last 2 hours → amber alert
   - All clear → single green "Systems nominal" message

2. **Recent Errors** — Last 20 failed jobs from `solid_queue` + `api_usage_logs`, showing:
   - Job class and article ID
   - Error message (truncated)
   - Timestamp (relative)

**Right Column (40% width):**

3. **API Usage by Model** — Aggregated from `api_usage_logs` for today:
   - Model name, call count, total cost
   - Sorted by cost descending

4. **Database Stats** — Table sizes:
   - Table name, row count, disk size
   - Top 5 largest tables
   - Capacity bar at bottom

5. **Ingestion Pipeline** — Computed from existing data:
   - Last successful fetch timestamp
   - Articles fetched today
   - Articles analyzed vs pending
   - Active sources (NewsAPI, GDELT)

## Components

### 1. Migration

`db/migrate/TIMESTAMP_create_api_usage_logs.rb`

### 2. Model

`app/models/api_usage_log.rb` — Minimal model with scopes:
- `scope :today` — created today
- `scope :successful` — status: success
- `scope :failed` — status: error
- `scope :by_model` — group by model
- Class method `total_cost_today` — sum of estimated_cost for today

### 3. Service

`app/services/system_health_service.rb` — Single service that gathers all dashboard data:

```ruby
class SystemHealthService
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
end
```

Returns a plain Hash consumed by the controller/view. No external API calls — everything from local DB queries.

### 4. Controller

`app/controllers/admin/dashboard_controller.rb`:

```ruby
class Admin::DashboardController < ApplicationController
  before_action :authenticate_user!
  before_action :require_admin!

  def show
    @health = SystemHealthService.new.call
  end

  private

  def require_admin!
    render plain: "Forbidden", status: :forbidden unless current_user.admin?
  end
end
```

### 5. View

`app/views/admin/dashboard/show.html.erb` — Single page with:
- Inline SVG donut gauges (no JS charting library)
- Cyberpunk dark theme matching existing admin views
- `data-controller="auto-refresh"` for 60-second reload

### 6. Stimulus Controller

`app/javascript/controllers/auto_refresh_controller.js` — Simple interval-based page reload:

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

### 7. Route

```ruby
namespace :admin do
  get "dashboard", to: "dashboard#show"
  # ... existing admin routes
end
```

### 8. Recurring Cleanup Job

Add to `config/recurring.yml`:

```yaml
prune_api_usage_logs:
  command: "ApiUsageLog.where('created_at < ?', 30.days.ago).delete_all"
  schedule: every day at 3am
```

### 9. OpenRouterClient Logging

Modify `OpenRouterClient#request_chat` to log after every call. The logging must not raise — wrap in `rescue` so a logging failure never breaks the analysis pipeline.

### 10. Navigation

Add a "Command Center" link to the admin section. Visible only to admin users.

## Styling

Match the existing cyberpunk aesthetic from `admin/users/index.html.erb`:
- Background: `#0a0e1a`
- Cards: `#1e293b` with `#334155` borders
- Accent: `#00f0ff` (cyan)
- Alerts: red `#ef4444`, amber `#f59e0b`, green `#22c55e`
- Font: JetBrains Mono for data, Space Grotesk for labels
- Uppercase labels with letter-spacing

## What This Does NOT Include

- Historical trends / charts over time (can be added later)
- Email or Slack alerting (alerts are on-page only)
- Neon API integration for exact transfer data (estimated only)
- User-facing health status (admin-only)
