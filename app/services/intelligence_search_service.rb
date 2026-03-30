# IntelligenceSearchService
# Orchestrates user-initiated live intelligence searches.
#
# Step A: Semantic search against existing articles (always instant, zero API calls)
# Step B: Decide whether to enqueue FreshIntelligenceJob for new NewsAPI data
# Step C: Return cached results + job metadata so the controller can respond immediately
#
# Design principle: the user always gets something back immediately.
# Fresh data arrives asynchronously via ActionCable broadcast.

class IntelligenceSearchService
  # Skip fresh fetch if this many fresh (< 48h) results already exist
  FRESH_RESULTS_CACHE_THRESHOLD = 10
  # Keep this many API calls in reserve before blocking fresh fetches
  API_CALLS_RESERVE = 10

  def self.call(query:, user: nil)
    new(query: query, user: user).call
  end

  def initialize(query:, user: nil)
    @query = query.to_s.strip
    @user  = user
  end

  def call
    return empty_result("Query is blank") if @query.blank?

    # Step A — semantic cache search
    cached_results, fresh_count = semantic_search

    # Step B — decide whether to enqueue fresh fetch
    job_enqueued, notice = maybe_enqueue_fresh_fetch(fresh_count)

    # Step C — return immediately
    {
      cached_results:     cached_results,
      total_cached:       cached_results.size,
      fresh_results_count: fresh_count,
      fetching_fresh:     job_enqueued,
      query:              @query,
      notice:             notice
    }
  rescue StandardError => e
    Rails.logger.error "[IntelligenceSearchService] #{e.class}: #{e.message}"
    empty_result("Search temporarily unavailable")
  end

  private

  def semantic_search
    if VeritasMode.demo?
      # Demo mode: text search against existing DB — no external API calls
      results = Article
        .where("headline ILIKE ? OR content ILIKE ?", "%#{@query}%", "%#{@query}%")
        .preload(:country, :region, :ai_analysis)
        .order(published_at: :desc)
        .limit(30)
        .to_a

      fresh_cutoff = 48.hours.ago
      fresh_count  = results.count { |a| a.published_at&.> fresh_cutoff }
      return [results, fresh_count]
    end

    vector = OpenRouterClient.new.embed(@query)

    unless vector.present?
      Rails.logger.warn "[IntelligenceSearchService] Embedding returned nil for query: '#{@query}'"
      return [[], 0]
    end

    # nearest_neighbors returns results ordered by cosine distance ascending.
    # No hard threshold — return top matches like the existing /search page does.
    # Preload associations AFTER materializing so neighbor_distance is preserved.
    article_ids = Article
      .nearest_neighbors(:embedding, vector, distance: "cosine")
      .limit(30)
      .pluck(:id)

    results = Article
      .where(id: article_ids)
      .preload(:country, :region, :ai_analysis)
      .sort_by { |a| article_ids.index(a.id) }  # preserve ranking order

    fresh_cutoff = 48.hours.ago
    fresh_count  = results.count { |a| a.published_at&.> fresh_cutoff }

    [results, fresh_count]
  rescue StandardError => e
    Rails.logger.error "[IntelligenceSearchService] Semantic search failed: #{e.message}"
    [[], 0]
  end

  def maybe_enqueue_fresh_fetch(fresh_count)
    # Demo mode: never enqueue fresh fetches
    if VeritasMode.demo?
      Rails.logger.info "[IntelligenceSearchService] Demo mode — skipping fresh fetch"
      return [false, nil]
    end

    # Don't burn API calls if the topic is well-covered with recent data
    if fresh_count >= FRESH_RESULTS_CACHE_THRESHOLD
      Rails.logger.info "[IntelligenceSearchService] #{fresh_count} fresh results found — skipping NewsAPI fetch"
      return [false, nil]
    end

    # Don't fetch if we're near the daily API limit
    if api_calls_remaining < API_CALLS_RESERVE
      return [false, "Using cached intelligence — daily API limit reached"]
    end

    # Atomic cache lock — prevents concurrent searches from enqueuing duplicate jobs.
    # NOTE: must NOT share the key with NewsApiService ("newsapi:search:...") which
    # uses Rails.cache.fetch on that namespace to store raw API results — writing
    # `true` there would poison the fetch cache and silently kill the API call.
    cache_key = "intelligence_search:fetch_lock:#{@query.parameterize}:#{Date.current}"
    unless Rails.cache.write(cache_key, true, expires_in: 6.hours, unless_exist: true)
      Rails.logger.info "[IntelligenceSearchService] Fetch already in-flight for '#{@query}' — skipping duplicate enqueue"
      return [true, nil]
    end

    FreshIntelligenceJob.perform_later(query: @query, user_id: @user&.id)
    Rails.logger.info "[IntelligenceSearchService] Enqueued FreshIntelligenceJob for '#{@query}'"
    [true, nil]
  rescue StandardError => e
    Rails.logger.error "[IntelligenceSearchService] Failed to enqueue job: #{e.message}"
    [false, nil]
  end

  def api_calls_remaining
    100 - Rails.cache.read("newsapi_calls:#{Date.today}").to_i
  end

  def empty_result(notice)
    {
      cached_results:      [],
      total_cached:        0,
      fresh_results_count: 0,
      fetching_fresh:      false,
      query:               @query,
      notice:              notice
    }
  end
end
