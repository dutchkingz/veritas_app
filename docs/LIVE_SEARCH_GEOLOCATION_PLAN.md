# LIVE INTELLIGENCE SEARCH + REAL GEOLOCATION — Implementation Plan

> Revised 2026-03-17. Replaces the original v1 plan.
> Principal Engineer review incorporated. Ready for implementation.

---

## Key Design Decisions (what changed from v1)

1. **Geolocation heuristic**: Use **last geographic entity in the title** as primary focus, not first. "US strikes targets in Syria" → Syria. Fall back to scanning description if title yields nothing.
2. **Cache threshold**: Return cached results **always** (even if just 1). Only skip fresh fetch if we have 10+ articles published within 48h *and* with similarity > 0.75. This prevents burning API calls on well-covered topics while never leaving the user empty-handed.
3. **Narrative routes on search**: Run `NarrativeRouteGeneratorService` only on **new articles against their 5 nearest existing neighbors** — not the full cached set. This keeps it O(n) instead of O(n²).
4. **Unknown fallback**: Use `nil` region + a dedicated `geo_method: "unresolved"` marker instead of `(0, 0)` in the Gulf of Guinea. The globe can filter these out.
5. **Error handling**: Every external call (NewsAPI, OpenRouter embeddings) gets a specific rescue with graceful degradation — never crash the search flow.
6. **API call tracking**: Use `Rails.cache` counter (not in-memory) so it survives restarts and works across Heroku dynos.

---

## TASK 1: GeolocatorService

**File:** `app/services/geolocator_service.rb`

### Algorithm (3-tier cascade)

#### Tier 1 — Keyword extraction from text
- Build `LOCATION_KEYWORDS` hash: ~80 entries mapping lowercase keywords → `{ country:, iso_code:, lat:, lng:, region_name: }`
- Include countries, capitals, major cities, conflict zones, geopolitical landmarks:
  - `"kremlin" → Russia`, `"pentagon" → USA`, `"gaza" → Palestine`, `"taipei" → Taiwan`
  - `"nato" → Belgium`, `"eu" → Belgium`, `"un" → USA (New York)`
  - All G20 nations + conflict hotspots (Ukraine, Syria, Yemen, Sudan, Myanmar, etc.)
- Scan `title + " " + description` (from `raw_data`)
- **Collect all matches with their character position in the text**
- **Primary location = last geographic entity mentioned in the TITLE** (this is usually the subject/location of the event). If no match in title, use last match in description.
- **Secondary location = first OTHER country mentioned** (often the actor). Store as `target_country` lookup.
- Return `{ country_name:, iso_code:, latitude:, longitude:, region_name:, geo_method: "keyword" }`

#### Tier 2 — Source-name fallback
- Build `SOURCE_COUNTRY_MAP` (~40 outlets):
  - `"Reuters" → UK`, `"Al Jazeera" → Qatar`, `"CNN" → USA`, `"RT" → Russia`, `"Xinhua" → China`
  - `"SCMP" → Hong Kong`, `"BBC" → UK`, `"Fox News" → USA`, `"Dawn" → Pakistan`
  - `"The Hindu" → India`, `"Folha" → Brazil`, `"Der Spiegel" → Germany`, `"Le Monde" → France`
  - `"NHK" → Japan`, `"Yonhap" → South Korea`, and ~25 more
- Match `source_name` against this map (case-insensitive, partial match)
- Return with `geo_method: "source_fallback"`

#### Tier 3 — Unknown
- Return `{ country_name: "Unknown", iso_code: nil, latitude: nil, longitude: nil, region_name: "Unknown", geo_method: "unresolved" }`
- **No (0,0) coordinates** — nil lat/lng means the globe skips these articles

### Region/Country DB linkage
After geo resolution, find matching Country + Region in DB by name/iso_code. If none found, assign to nearest existing region by haversine distance, or nil. Return the final hash with `region:`, `country:`, `latitude:`, `longitude:`, `geo_method:`.

---

## TASK 2: IntelligenceSearchService

**File:** `app/services/intelligence_search_service.rb`

### Step A — Semantic cache check
1. Generate embedding for the query string via `OpenRouterClient.new.embed(query)`
2. Search existing articles using pgvector: `Article.nearest_neighbors(:embedding, vector, distance: "cosine").limit(50)`
3. Filter results to those with cosine distance < 0.4 (similarity > 0.6)
4. Separate into `fresh` (published < 48h) and `older` results
5. **Always return all cached matches immediately**

### Step B — Decide whether to fetch fresh
- **Skip fresh fetch if:**
  - `fresh.count >= 10` (well-covered topic, don't waste API calls)
  - OR `api_calls_remaining < 10` (preserve last calls for other users)
- **Otherwise:** enqueue `FreshIntelligenceJob.perform_later(query:, query_embedding: vector, user_id: user&.id)`
- Track API calls: `Rails.cache.increment("newsapi_calls:#{Date.today}", 1, expires_in: 24.hours)`

### Step C — Return shape
```ruby
{
  cached_results: articles,        # ActiveRecord array, immediate
  total_cached: articles.size,
  fresh_results_count: fresh.size,
  fetching_fresh: job_enqueued?,
  fresh_job_id: job&.provider_job_id,
  query: query,
  notice: notice                   # nil or "Using cached intelligence — daily API limit reached"
}
```

---

## TASK 2b: FreshIntelligenceJob

**File:** `app/jobs/fresh_intelligence_job.rb`

### Pipeline
1. **Fetch** — `NewsApiService.new.fetch_by_query(query, max_results: 20)`
2. **Dedup** — filter out articles whose `source_url` already exists in DB
3. **Geolocate** — `GeolocatorService.call(article_attrs)` for each new article (no API calls, pure keyword matching)
4. **Save** — `Article.create!(attrs)` for each; rescue individually so one bad article doesn't kill the batch
5. **Embed** — Generate embeddings for all new articles via `EmbeddingService`
6. **Narrative Routes (SMART)** — For each new article with an embedding:
   - Find its 5 nearest neighbors from the **existing** article pool via pgvector
   - Call `NarrativeRouteGeneratorService.new.generate_routes_for_article(article)` (targeted method, not full O(n²) pass)
7. **Broadcast** — Turbo Stream to notify frontend; globe channel picks up new articles via existing `after_create_commit :broadcast_to_globe`

### Error handling
- NewsAPI 429 → log, broadcast "API limit reached", return gracefully
- Embedding fails → skip embedding, save article anyway (article is in DB, just not searchable via vector until re-embedded)
- Route generation fails → log and continue (routes are enhancement, not critical path)

---

## TASK 3: Search Endpoint

**File:** `app/controllers/api/search_controller.rb`

- `POST /api/search` — accepts `{ query: "..." }`, calls `IntelligenceSearchService`, returns JSON
- Rate limit: 5 searches/minute per session using `Rails.cache` (durable across restarts)
- If daily API limit approached (< 10 calls remaining), skip fresh fetch and return cached only with notice
- Lean JSON response: `id, headline, source_name, latitude, longitude, published_at, country, region, trust_score, threat_level, sentiment_color, geo_method`

---

## TASK 4: Update NewsApiService

### 4a — Replace random assignment with GeolocatorService
In both `fetch_latest` and `fetch_demo_batch`, replace:
```ruby
region = regions.sample
country = region.countries.first
```
With:
```ruby
geo = GeolocatorService.call(item)
```
Remove the `rand(-2.0..2.0)` coordinate jitter — real coordinates are more accurate.

### 4b — Add `fetch_by_query` method
```ruby
def fetch_by_query(query_string, max_results: 20)
  return [] if @api_key.blank?
  return [] if api_limit_reached?
  raw = call_api(query: query_string, page_size: [max_results, 100].min, page: 1)
  track_api_call!
  # dedup, geolocate, return attrs
end
```

### 4c — API limit tracking (private)
```ruby
def api_limit_reached? = calls_today >= 90  # leave 10-call buffer
def calls_today = Rails.cache.read("newsapi_calls:#{Date.today}").to_i
def track_api_call! = Rails.cache.increment("newsapi_calls:#{Date.today}", 1, expires_in: 24.hours)
```

---

## TASK 4b: Extend NarrativeRouteGeneratorService

Add a targeted public method:
```ruby
def generate_routes_for_article(article)
  return 0 unless article.embedding.present?
  similar = find_similar_articles(article)
  return 0 if similar.empty?
  create_route_for_article(article, similar)
end
```
This exposes per-article route generation without running the full O(n²) sweep.

---

## TASK 5: Migration

**File:** `db/migrate/XXXXXX_add_geo_method_to_articles.rb`

```ruby
class AddGeoMethodToArticles < ActiveRecord::Migration[8.0]
  def change
    add_column :articles, :geo_method, :string, default: "unresolved"
    change_column_null :articles, :region_id, true
    change_column_null :articles, :country_id, true
  end
end
```

`geo_method` values: `"keyword"`, `"source_fallback"`, `"unresolved"`
Analysts can filter globe to show only `"keyword"` articles for trustworthy placements.

---

## Files Created/Modified (Summary)

| Action | File |
|--------|------|
| **CREATE** | `app/services/geolocator_service.rb` |
| **CREATE** | `app/services/intelligence_search_service.rb` |
| **CREATE** | `app/jobs/fresh_intelligence_job.rb` |
| **CREATE** | `app/controllers/api/search_controller.rb` |
| **CREATE** | `db/migrate/XXXXXX_add_geo_method_to_articles.rb` |
| **MODIFY** | `app/services/news_api_service.rb` |
| **MODIFY** | `app/services/narrative_route_generator_service.rb` |
| **MODIFY** | `config/routes.rb` |

---

## Cost Analysis (Free Tier Budget)

| Operation | NewsAPI calls | OpenRouter embed calls |
|-----------|--------------|----------------------|
| Background scheduled fetch (existing) | 6/run | 0 |
| User search — fresh fetch | 1 per search | 1 (query) + N (new articles) |
| User search — cached only | 0 | 1 (query only) |
| Daily budget | 100 total | pay-per-token |

With smart caching (skip fetch if 10+ fresh results exist), a typical day with 5-10 user searches consumes ~15-20 NewsAPI calls — well within the 100/day budget.

---

## Constraints (unchanged)
- No JS/view/controller changes outside new API controller
- No globe_controller.js modifications
- No embedding model changes
- No new gems
- Existing services extended, not replaced
- All services use `.call` class method pattern
- Rails 8 conventions throughout
