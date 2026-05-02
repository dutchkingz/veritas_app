# IntelligenceSearchService
# Orchestrates user-initiated live intelligence searches.
#
# Step A: Semantic search against existing articles (always instant, zero API calls)
# Step B: Build narrative relationships between results (framing, entities, routes)
# Step C: Decide whether to enqueue FreshIntelligenceJob for new NewsAPI data
# Step D: Return cached results + narrative intelligence + job metadata
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

    # Step B — build narrative relationships between results
    narrative_intel = build_narrative_intelligence(cached_results)

    # Step C — decide whether to enqueue fresh fetch
    job_enqueued, notice = maybe_enqueue_fresh_fetch(fresh_count)

    # Step D — return immediately
    {
      cached_results:      cached_results,
      total_cached:        cached_results.size,
      fresh_results_count: fresh_count,
      fetching_fresh:      job_enqueued,
      query:               @query,
      notice:              notice,
      narrative_intel:      narrative_intel
    }
  rescue StandardError => e
    Rails.logger.error "[IntelligenceSearchService] #{e.class}: #{e.message}"
    empty_result("Search temporarily unavailable")
  end

  private

  # Maximum cosine distance for pgvector results. Articles beyond this
  # threshold are too dissimilar to the query and get filtered out.
  # cosine_distance = 1 - cosine_similarity, so 0.35 ≈ 65% similarity minimum.
  MAX_COSINE_DISTANCE = 0.35

  def semantic_search
    if VeritasMode.demo?
      return demo_text_search
    end

    vector = OpenRouterClient.new.embed(@query)

    unless vector.present?
      Rails.logger.warn "[IntelligenceSearchService] Embedding returned nil for query: '#{@query}'"
      return [[], 0]
    end

    # nearest_neighbors returns results ordered by cosine distance ascending.
    # Apply a similarity threshold — don't return garbage just to fill 30 slots.
    candidates = Article
      .nearest_neighbors(:embedding, vector, distance: "cosine")
      .limit(30)

    # Filter by threshold: only keep articles with meaningful similarity
    article_ids = candidates.select { |a| a.neighbor_distance <= MAX_COSINE_DISTANCE }.map(&:id)

    if article_ids.empty?
      Rails.logger.info "[IntelligenceSearchService] No articles above similarity threshold for '#{@query}'"
      return [[], 0]
    end

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

  # Demo mode: word-level matching instead of naive substring ILIKE.
  # Splits the query into keywords and requires ALL keywords to appear
  # in headline OR content. This prevents "war ships" from matching a
  # Final Fantasy article that happens to contain "war" in an unrelated context.
  def demo_text_search
    keywords = @query.downcase.split(/\s+/).reject { |w| w.length < 2 }
    return [[], 0] if keywords.empty?

    # Each keyword must appear in headline OR content (AND logic across keywords)
    scope = Article.preload(:country, :region, :ai_analysis)

    # Build parameterized WHERE conditions — one per keyword
    where_clauses = []
    where_params = []
    headline_clauses = []
    headline_params = []

    keywords.each do |kw|
      pattern = "%#{ActiveRecord::Base.sanitize_sql_like(kw)}%"
      where_clauses << "(headline ILIKE ? OR content ILIKE ?)"
      where_params.push(pattern, pattern)
      headline_clauses << "headline ILIKE ?"
      headline_params << pattern
    end

    # Prioritize headline matches over content-only matches
    order_sql = ActiveRecord::Base.sanitize_sql_array(
      ["CASE WHEN #{headline_clauses.join(' AND ')} THEN 0 ELSE 1 END ASC, published_at DESC"] + headline_params
    )

    results = scope
      .where(where_clauses.join(" AND "), *where_params)
      .order(Arel.sql(order_sql))
      .limit(30)
      .to_a

    fresh_cutoff = 48.hours.ago
    fresh_count  = results.count { |a| a.published_at&.> fresh_cutoff }
    [results, fresh_count]
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

  # ──────────────────────────────────────────────────────────────
  # Narrative Intelligence Builder
  # ──────────────────────────────────────────────────────────────
  # Given a set of search results, computes how they relate to each
  # other through narrative routes, framing shifts, and shared entities.
  # Returns lightweight relationship data — no LLM calls, pure DB lookups.

  def build_narrative_intelligence(articles)
    return empty_narrative_intel if articles.size < 2

    article_ids = articles.map(&:id)

    # 1. Narrative route connections — articles linked through propagation chains
    route_connections = find_route_connections(article_ids)

    # 2. Shared entity connections — articles mentioning the same people/orgs/places
    entity_connections = find_shared_entities(article_ids)

    # 3. Framing clusters — group articles by how they frame the same narrative
    framing_clusters = build_framing_clusters(article_ids)

    # 4. Contradiction flags — known contradictions between result articles
    contradictions = find_contradictions(article_ids)

    # 5. Narrative signatures — recurring narrative patterns these articles belong to
    signatures = find_narrative_signatures(article_ids)

    {
      route_connections:  route_connections,
      entity_connections: entity_connections,
      framing_clusters:   framing_clusters,
      contradictions:     contradictions,
      signatures:         signatures,
      relationship_count: route_connections.size + entity_connections.size
    }
  rescue StandardError => e
    Rails.logger.warn "[IntelligenceSearchService] Narrative intel failed: #{e.message}"
    empty_narrative_intel
  end

  # ── 1. Narrative Route Connections ──
  # Find articles that appear in the same narrative propagation chain.
  # Returns which articles are connected and how (framing shift, confidence).
  def find_route_connections(article_ids)
    # Find all narrative arcs originating from these articles
    arc_ids = NarrativeArc.where(article_id: article_ids).pluck(:id)
    return [] if arc_ids.empty?

    routes = NarrativeRoute.where(narrative_arc_id: arc_ids)
                           .where("total_hops >= ?", 1)
                           .includes(narrative_arc: :article)
                           .to_a

    connections = []

    routes.each do |route|
      origin_id = route.narrative_arc&.article_id
      hop_article_ids = route.hops.filter_map { |h| h["article_id"] }
      route_article_ids = ([origin_id] + hop_article_ids).compact.uniq

      # Only include connections where both articles are in the search results
      matched_ids = route_article_ids & article_ids
      next if matched_ids.size < 2

      # Build pairwise connections along the chain
      route_article_ids.each_cons(2) do |source_id, target_id|
        next unless article_ids.include?(source_id) && article_ids.include?(target_id)

        hop = route.hops.find { |h| h["article_id"] == target_id }
        connections << {
          source_id:    source_id,
          target_id:    target_id,
          type:         "narrative_route",
          framing:      hop&.dig("framing_shift") || "unknown",
          explanation:  hop&.dig("framing_explanation"),
          confidence:   hop&.dig("confidence_score").to_f,
          route_name:   route.name
        }
      end
    end

    connections.uniq { |c| [c[:source_id], c[:target_id]].sort }
  end

  # ── 2. Shared Entities ──
  # Find named entities (people, orgs, places) shared between search result articles.
  def find_shared_entities(article_ids)
    return [] if article_ids.size < 2

    sql = <<~SQL
      SELECT em1.article_id AS source_id,
             em2.article_id AS target_id,
             COUNT(DISTINCT em1.entity_id) AS shared_count,
             ARRAY_AGG(DISTINCT e.name ORDER BY e.name) AS entity_names
      FROM entity_mentions em1
      JOIN entity_mentions em2 ON em1.entity_id = em2.entity_id
                               AND em1.article_id < em2.article_id
      JOIN entities e ON e.id = em1.entity_id
      WHERE em1.article_id IN (?)
        AND em2.article_id IN (?)
      GROUP BY em1.article_id, em2.article_id
      HAVING COUNT(DISTINCT em1.entity_id) >= 1
      ORDER BY shared_count DESC
      LIMIT 50
    SQL

    results = ActiveRecord::Base.connection.select_all(
      ActiveRecord::Base.send(:sanitize_sql_array, [sql, article_ids, article_ids])
    )

    results.map do |row|
      raw_names = row["entity_names"].to_s
      names = raw_names.delete_prefix("{").delete_suffix("}").split(",").map { |n| n.delete('"').strip }

      {
        source_id:    row["source_id"].to_i,
        target_id:    row["target_id"].to_i,
        type:         "shared_entities",
        entities:     names.first(5),
        shared_count: row["shared_count"].to_i
      }
    end
  end

  # ── 3. Framing Clusters ──
  # Group articles by framing type using existing NarrativeRoute hop data.
  # Articles that are "distorted" or "amplified" re the same origin form clusters.
  def build_framing_clusters(article_ids)
    # Pull framing data from narrative route hops
    routes = NarrativeRoute.joins(:narrative_arc)
                           .where(narrative_arcs: { article_id: article_ids })
                           .to_a

    framing_map = {} # article_id => { framing:, origin_id:, explanation: }

    routes.each do |route|
      origin_id = route.narrative_arc&.article_id
      route.hops.each do |hop|
        aid = hop["article_id"]
        next unless aid && article_ids.include?(aid)
        framing = hop["framing_shift"]
        next if framing.blank? || framing == "original"

        framing_map[aid] = {
          framing:     framing,
          origin_id:   origin_id,
          explanation: hop["framing_explanation"],
          confidence:  hop["confidence_score"].to_f
        }
      end
    end

    # Group by framing type
    clusters = framing_map.group_by { |_, v| v[:framing] }
    clusters.transform_values { |pairs| pairs.map { |aid, data| data.merge(article_id: aid) } }
  end

  # ── 4. Contradictions ──
  # Surface known contradictions between articles in the result set.
  def find_contradictions(article_ids)
    return [] if article_ids.size < 2

    ContradictionLog.where(article_a_id: article_ids, article_b_id: article_ids)
                    .order(severity: :desc)
                    .limit(10)
                    .map do |c|
      {
        article_a_id: c.article_a_id,
        article_b_id: c.article_b_id,
        severity:     c.severity,
        description:  c.description
      }
    end
  rescue StandardError
    [] # ContradictionLog may not exist in all environments
  end

  # ── 5. Narrative Signatures ──
  # Find recurring narrative patterns these articles belong to.
  def find_narrative_signatures(article_ids)
    NarrativeSignature.joins(:narrative_signature_articles)
                      .where(narrative_signature_articles: { article_id: article_ids })
                      .select("narrative_signatures.*, COUNT(narrative_signature_articles.id) AS match_count")
                      .group("narrative_signatures.id")
                      .order("match_count DESC")
                      .limit(5)
                      .map do |sig|
      {
        id:          sig.id,
        label:       sig.label,
        match_count: sig.match_count,
        description: sig.try(:description)
      }
    end
  rescue StandardError
    [] # NarrativeSignature may not exist in all environments
  end

  def empty_narrative_intel
    {
      route_connections:  [],
      entity_connections: [],
      framing_clusters:   {},
      contradictions:     [],
      signatures:         [],
      relationship_count: 0
    }
  end

  def empty_result(notice)
    {
      cached_results:      [],
      total_cached:        0,
      fresh_results_count: 0,
      fetching_fresh:      false,
      query:               @query,
      notice:              notice,
      narrative_intel:      empty_narrative_intel
    }
  end
end
