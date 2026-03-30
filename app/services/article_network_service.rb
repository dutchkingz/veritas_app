# frozen_string_literal: true

# ArticleNetworkService — Central network graph builder for VERITAS
#
# Computes multi-type connections between articles using four signal channels:
#   1. NarrativeRoute (1.0) — actual narrative propagation chains
#   2. GDELT Event    (0.8) — real-world event correlation
#   3. Embedding       (0.6) — pgvector semantic similarity
#   4. Shared Entities (0.3) — entity overlap via NER
#
# Returns { articles: [], arcs: [], meta: {} } for globe rendering.
class ArticleNetworkService
  # Connection type weights — NarrativeRoute dominates by design.
  # pgvector expands the network but does NOT define it.
  WEIGHTS = {
    narrative_route:    1.0,
    gdelt_event:        0.8,
    embedding_similarity: 0.6,
    shared_entities:    0.3
  }.freeze

  # Similarity threshold for pgvector expansion (same as NarrativeRouteGeneratorService)
  EMBEDDING_THRESHOLD = 0.65
  # Max cosine distance = 1 - similarity
  MAX_COSINE_DISTANCE = 1.0 - EMBEDDING_THRESHOLD

  # Minimum combined strength to include a connection
  MIN_STRENGTH = 0.15

  # Render cap for frontend (rest goes to sidebar/meta only)
  RENDER_LIMIT = 60

  CACHE_TTL = 12.hours

  def initialize(logger: Rails.logger)
    @logger = logger
  end

  # ──────────────────────────────────────────────────────────────
  # Public API
  # ──────────────────────────────────────────────────────────────

  # Network around ONE article, expanding outward.
  # depth: 1 = direct connections, 2 = friends-of-friends
  # time_window: only articles within ±time_window of the center
  def network_for_article(article, depth: 2, time_window: 48.hours)
    cache_key = "article_network:#{article.id}:d#{depth}:t#{time_window.to_i}"

    Rails.cache.fetch(cache_key, expires_in: CACHE_TTL) do
      @logger.info "[ArticleNetwork] Building network for Article ##{article.id} (depth=#{depth})"
      build_network_for_article(article, depth, time_window)
    end
  end

  # Connections WITHIN an article group (for Global View / Search View).
  # Does NOT expand — only finds connections between the given articles.
  def connections_between(articles, time_window: 48.hours)
    return empty_result if articles.blank? || articles.size < 2

    article_ids = articles.map(&:id).sort
    cache_key = "article_connections:#{Digest::MD5.hexdigest(article_ids.join(','))}:t#{time_window.to_i}"

    Rails.cache.fetch(cache_key, expires_in: CACHE_TTL) do
      @logger.info "[ArticleNetwork] Finding connections between #{articles.size} articles"
      build_connections_between(articles, time_window)
    end
  end

  private

  # ──────────────────────────────────────────────────────────────
  # Network Builder (depth expansion)
  # ──────────────────────────────────────────────────────────────

  def build_network_for_article(center, depth, time_window)
    time_range = time_range_for(center, time_window)
    visited = Set.new([center.id])
    all_connections = []
    current_layer = [center]

    (1..depth).each do |d|
      next_layer_ids = Set.new
      layer_articles = preload_articles(current_layer.map(&:id))

      # Find all connections for current layer
      connections = find_connections_for(layer_articles, time_range, visited)

      connections.each do |conn|
        conn[:depth] = d
        all_connections << conn

        # Collect new article IDs for next layer
        [conn[:source_article_id], conn[:target_article_id]].each do |aid|
          next_layer_ids << aid unless visited.include?(aid)
        end
      end

      visited.merge(next_layer_ids)

      # For depth 2, only follow strong connections (NarrativeRoute or high similarity)
      if d < depth
        current_layer = Article.where(id: next_layer_ids.to_a).to_a
      end
    end

    # Deduplicate connections (same pair may be found from both sides)
    unique_connections = deduplicate_connections(all_connections)

    # Load all network articles
    all_article_ids = visited.to_a
    network_articles = preload_articles(all_article_ids)

    build_result(center, network_articles, unique_connections)
  end

  # ──────────────────────────────────────────────────────────────
  # Connections Between (no expansion)
  # ──────────────────────────────────────────────────────────────

  def build_connections_between(articles, time_window)
    article_ids = articles.map(&:id)
    loaded = preload_articles(article_ids)
    time_range = (articles.filter_map(&:published_at).min - time_window)..(articles.filter_map(&:published_at).max + time_window)

    connections = []

    # 1. NarrativeRoute connections (highest priority)
    connections += find_narrative_route_connections(article_ids)

    # 2. GDELT Event connections
    connections += find_gdelt_connections(article_ids)

    # 3. Embedding similarity connections
    connections += find_embedding_connections_within(loaded, article_ids)

    # 4. Shared entity connections
    connections += find_entity_connections(article_ids)

    unique = deduplicate_connections(connections)
    build_result(nil, loaded, unique)
  end

  # ──────────────────────────────────────────────────────────────
  # Connection Finders (batch queries, no N+1)
  # ──────────────────────────────────────────────────────────────

  # Find all connection types for a set of articles, excluding already-visited
  def find_connections_for(articles, time_range, visited)
    article_ids = articles.map(&:id)
    connections = []

    connections += find_narrative_route_connections(article_ids, visited)
    connections += find_gdelt_connections(article_ids, visited)
    connections += find_embedding_connections(articles, time_range, visited)
    connections += find_entity_connections(article_ids, visited)

    connections
  end

  # ── 1. NarrativeRoute connections ──
  # Articles that appear in the same route's hops = narrative propagation link.
  def find_narrative_route_connections(article_ids, excluded_ids = Set.new)
    # Find all routes that reference any of these articles (via hops JSONB)
    arc_ids = NarrativeArc.where(article_id: article_ids).pluck(:id)
    return [] if arc_ids.empty?

    routes = NarrativeRoute
      .where(narrative_arc_id: arc_ids)
      .includes(narrative_arc: { article: [:ai_analysis, :country] })
      .to_a

    connections = []

    routes.each do |route|
      hop_article_ids = route.hops.filter_map { |h| h["article_id"] }.uniq
      origin_id = route.narrative_arc&.article_id

      # All articles in this route (origin + hops)
      route_article_ids = ([origin_id] + hop_article_ids).compact.uniq

      # Find pairs where at least one is in our article_ids set
      relevant = route_article_ids & article_ids
      next if relevant.empty?

      # Create connections between consecutive hops
      route_article_ids.each_cons(2) do |source_id, target_id|
        next if excluded_ids.include?(source_id) && excluded_ids.include?(target_id)
        next unless source_id && target_id
        next if source_id == target_id

        # At least one must be in our set
        next unless article_ids.include?(source_id) || article_ids.include?(target_id)

        hop_data = route.hops.find { |h| h["article_id"] == target_id }

        connections << {
          source_article_id: source_id,
          target_article_id: target_id,
          connection_types: [:narrative_route],
          type_strengths: { narrative_route: WEIGHTS[:narrative_route] },
          route_id: route.id,
          framing: hop_data&.dig("framing_shift"),
          framing_explanation: hop_data&.dig("framing_explanation"),
          confidence: hop_data&.dig("confidence_score").to_f
        }
      end
    end

    connections
  end

  # ── 2. GDELT Event connections ──
  # Articles whose GDELT events share actors or event codes.
  def find_gdelt_connections(article_ids, excluded_ids = Set.new)
    events = GdeltEvent.where(article_id: article_ids).to_a
    return [] if events.empty?

    events_by_article = events.group_by(&:article_id)
    connections = []

    # Group events by actor pair for cross-referencing
    actor_index = Hash.new { |h, k| h[k] = [] }
    events.each do |event|
      key = normalize_actor_pair(event.actor1_name, event.actor2_name)
      actor_index[key] << event if key
    end

    # Also index by event root code
    code_index = Hash.new { |h, k| h[k] = [] }
    events.each do |event|
      code_index[event.event_root_code] << event if event.event_root_code.present?
    end

    # Find connections: same actor pair across different articles
    seen_pairs = Set.new

    [actor_index, code_index].each do |index|
      index.each_value do |group|
        article_id_set = group.map(&:article_id).compact.uniq
        next if article_id_set.size < 2

        article_id_set.combination(2).each do |a_id, b_id|
          pair = [a_id, b_id].sort
          next if seen_pairs.include?(pair)
          next if excluded_ids.include?(a_id) && excluded_ids.include?(b_id)

          seen_pairs << pair
          event_a = events_by_article[a_id]&.first
          event_b = events_by_article[b_id]&.first
          best_event = [event_a, event_b].compact.min_by { |e| e.goldstein_scale || 0 }

          connections << {
            source_article_id: pair[0],
            target_article_id: pair[1],
            connection_types: [:gdelt_event],
            type_strengths: { gdelt_event: WEIGHTS[:gdelt_event] },
            event_description: best_event&.event_description,
            actor_summary: best_event&.actor_summary,
            goldstein_scale: best_event&.goldstein_scale,
            quad_class: best_event&.quad_class
          }
        end
      end
    end

    connections
  end

  # ── 3. Embedding Similarity connections ──
  # pgvector nearest neighbors — EXPANDS the network, doesn't define it.
  def find_embedding_connections(articles, time_range, excluded_ids = Set.new)
    articles_with_embeddings = articles.select { |a| a.embedding.present? }
    return [] if articles_with_embeddings.empty?

    connections = []
    already_found = Set.new

    # Batch: one pgvector query per article (unavoidable for nearest-neighbor)
    # but we limit to 5 neighbors each to keep it fast
    articles_with_embeddings.each do |article|
      sql = <<~SQL
        SELECT id, embedding <=> '#{article.embedding.to_json}'::vector AS distance
        FROM articles
        WHERE id != #{article.id}
          AND embedding IS NOT NULL
          AND published_at BETWEEN '#{time_range.begin.iso8601}' AND '#{time_range.end.iso8601}'
        ORDER BY embedding <=> '#{article.embedding.to_json}'::vector
        LIMIT 8
      SQL

      results = ActiveRecord::Base.connection.execute(sql)

      results.each do |row|
        target_id = row["id"].to_i
        distance = row["distance"].to_f
        next if distance >= MAX_COSINE_DISTANCE
        next if excluded_ids.include?(target_id) && excluded_ids.include?(article.id)

        pair = [article.id, target_id].sort
        next if already_found.include?(pair)
        already_found << pair

        similarity = ((1.0 - distance) * 100).round
        connections << {
          source_article_id: pair[0],
          target_article_id: pair[1],
          connection_types: [:embedding_similarity],
          type_strengths: { embedding_similarity: WEIGHTS[:embedding_similarity] * (1.0 - distance) },
          semantic_similarity: similarity
        }
      end
    end

    connections
  end

  # Variant for connections_between: only find similarities within the given set
  def find_embedding_connections_within(articles, article_ids)
    articles_with_embeddings = articles.select { |a| a.embedding.present? }
    return [] if articles_with_embeddings.size < 2

    connections = []
    already_found = Set.new

    # Single batch query: all-vs-all within the set
    articles_with_embeddings.each do |article|
      other_ids = (article_ids - [article.id])
      next if other_ids.empty?

      sql = <<~SQL
        SELECT id, embedding <=> '#{article.embedding.to_json}'::vector AS distance
        FROM articles
        WHERE id IN (#{other_ids.join(',')})
          AND embedding IS NOT NULL
        ORDER BY embedding <=> '#{article.embedding.to_json}'::vector
        LIMIT 10
      SQL

      results = ActiveRecord::Base.connection.execute(sql)

      results.each do |row|
        target_id = row["id"].to_i
        distance = row["distance"].to_f
        next if distance >= MAX_COSINE_DISTANCE

        pair = [article.id, target_id].sort
        next if already_found.include?(pair)
        already_found << pair

        similarity = ((1.0 - distance) * 100).round
        connections << {
          source_article_id: pair[0],
          target_article_id: pair[1],
          connection_types: [:embedding_similarity],
          type_strengths: { embedding_similarity: WEIGHTS[:embedding_similarity] * (1.0 - distance) },
          semantic_similarity: similarity
        }
      end
    end

    connections
  end

  # ── 4. Shared Entity connections ──
  # Articles that share named entities (persons, organizations, etc.)
  def find_entity_connections(article_ids, excluded_ids = Set.new)
    return [] if article_ids.empty?

    # Single SQL: find article pairs sharing entities
    sql = <<~SQL
      SELECT em1.article_id AS source_id,
             em2.article_id AS target_id,
             COUNT(DISTINCT em1.entity_id) AS shared_count,
             ARRAY_AGG(DISTINCT e.name ORDER BY e.name) AS entity_names
      FROM entity_mentions em1
      JOIN entity_mentions em2 ON em1.entity_id = em2.entity_id
                               AND em1.article_id < em2.article_id
      JOIN entities e ON e.id = em1.entity_id
      WHERE em1.article_id IN (#{article_ids.join(',')})
        AND em2.article_id IN (#{article_ids.join(',')})
      GROUP BY em1.article_id, em2.article_id
      HAVING COUNT(DISTINCT em1.entity_id) >= 2
      ORDER BY shared_count DESC
      LIMIT 100
    SQL

    results = ActiveRecord::Base.connection.execute(sql)

    results.filter_map do |row|
      source_id = row["source_id"].to_i
      target_id = row["target_id"].to_i
      next if excluded_ids.include?(source_id) && excluded_ids.include?(target_id)

      shared_count = row["shared_count"].to_i
      # Parse PG array: "{\"name1\",\"name2\"}" → ["name1", "name2"]
      raw_names = row["entity_names"].to_s
      entity_names = raw_names.delete_prefix("{").delete_suffix("}").split(",").map { |n| n.delete('"').strip }

      # Strength scales with shared entity count (diminishing returns)
      entity_strength = WEIGHTS[:shared_entities] * Math.log2(shared_count + 1) / Math.log2(5)

      {
        source_article_id: source_id,
        target_article_id: target_id,
        connection_types: [:shared_entities],
        type_strengths: { shared_entities: entity_strength.clamp(0.0, WEIGHTS[:shared_entities]) },
        shared_entities: entity_names.first(5),
        shared_entity_count: shared_count
      }
    end
  end

  # ──────────────────────────────────────────────────────────────
  # Merging & Deduplication
  # ──────────────────────────────────────────────────────────────

  def deduplicate_connections(connections)
    merged = {}

    connections.each do |conn|
      pair = [conn[:source_article_id], conn[:target_article_id]].sort
      key = pair.join("-")

      if merged[key]
        existing = merged[key]
        # Merge connection types
        existing[:connection_types] = (existing[:connection_types] + conn[:connection_types]).uniq
        # Merge type strengths (keep highest per type)
        conn[:type_strengths]&.each do |type, strength|
          existing[:type_strengths][type] = [existing[:type_strengths][type].to_f, strength].max
        end
        # Merge metadata (prefer non-nil)
        %i[framing framing_explanation route_id event_description actor_summary
           goldstein_scale quad_class semantic_similarity shared_entities
           shared_entity_count confidence].each do |field|
          existing[field] = conn[field] if conn[field].present? && existing[field].blank?
        end
        # Use minimum depth
        existing[:depth] = [existing[:depth].to_i, conn[:depth].to_i].reject(&:zero?).min if conn[:depth]
      else
        merged[key] = conn.dup
        merged[key][:source_article_id] = pair[0]
        merged[key][:target_article_id] = pair[1]
      end
    end

    # Calculate combined strength for each connection
    merged.each_value do |conn|
      conn[:strength] = calculate_combined_strength(conn[:type_strengths])
    end

    # Filter by minimum strength and sort
    merged.values
      .select { |c| c[:strength] >= MIN_STRENGTH }
      .sort_by { |c| -c[:strength] }
  end

  # Combined strength: weighted sum of all applicable types.
  # Multiple overlapping types = stronger signal (capped at 1.0).
  def calculate_combined_strength(type_strengths)
    return 0.0 if type_strengths.blank?

    total = type_strengths.values.sum
    total.clamp(0.0, 1.0).round(3)
  end

  # ──────────────────────────────────────────────────────────────
  # Result Builder
  # ──────────────────────────────────────────────────────────────

  def build_result(center, articles, connections)
    articles_by_id = articles.index_by(&:id)

    # Enrich connections with article data for globe rendering
    arcs = connections.filter_map do |conn|
      source = articles_by_id[conn[:source_article_id]]
      target = articles_by_id[conn[:target_article_id]]
      next unless source && target
      next unless source.latitude && source.longitude && target.latitude && target.longitude

      build_arc(source, target, conn, center)
    end

    # Sort by strength, apply render limit
    arcs.sort_by! { |a| -a[:strength] }

    article_nodes = articles.filter_map do |a|
      next unless a.latitude && a.longitude
      build_article_node(a, center)
    end

    type_counts = connections.each_with_object(Hash.new(0)) do |c, counts|
      c[:connection_types].each { |t| counts[t] += 1 }
    end

    {
      articles: article_nodes,
      arcs: arcs,
      meta: {
        center_article_id: center&.id,
        total_connections: connections.size,
        rendered_connections: [arcs.size, RENDER_LIMIT].min,
        render_limit: RENDER_LIMIT,
        connection_types: type_counts,
        total_articles: articles.size
      }
    }
  end

  def build_arc(source, target, conn, center)
    # Compute veritasThreatScore-based color
    source_threat = source.ai_analysis&.threat_level.to_s
    target_threat = target.ai_analysis&.threat_level.to_s
    threat_score = compute_arc_threat_score(source_threat, target_threat, conn)
    color = threat_score_to_color(threat_score)

    # Thickness: score × confidence × connection_strength
    confidence = conn[:confidence].to_f.clamp(0.1, 1.0)
    confidence = 0.7 if confidence < 0.1 # default confidence
    thickness = (threat_score / 10.0 * confidence * conn[:strength]).clamp(0.2, 2.0).round(2)

    # Opacity from confidence
    opacity = confidence.clamp(0.3, 1.0)
    # Depth 2 reduction
    opacity *= 0.5 if conn[:depth].to_i >= 2

    # Sentiment shift
    source_sentiment = source.ai_analysis&.sentiment_label.to_s
    target_sentiment = target.ai_analysis&.sentiment_label.to_s
    sentiment_shift = build_sentiment_shift(source_sentiment, target_sentiment)

    {
      id: "net-#{conn[:source_article_id]}-#{conn[:target_article_id]}",
      sourceArticleId: conn[:source_article_id],
      targetArticleId: conn[:target_article_id],
      startLat: source.latitude,
      startLng: source.longitude,
      endLat: target.latitude,
      endLng: target.longitude,
      color: color,
      thickness: thickness,
      opacity: opacity,
      strength: conn[:strength],
      connectionTypes: conn[:connection_types],
      depth: conn[:depth] || 1,
      veritasThreatScore: threat_score,
      arcConfidence: confidence.round(2),
      # Source info
      sourceName: source.source_name,
      sourceCountry: source.country&.name,
      sourceHeadline: source.headline,
      sourceThreatLevel: source_threat,
      sourceSentimentLabel: source_sentiment,
      # Target info
      targetSourceName: target.source_name,
      targetCountry: target.country&.name,
      targetHeadline: target.headline,
      targetThreatLevel: target_threat,
      targetSentimentLabel: target_sentiment,
      # Analysis
      semanticSimilarity: conn[:semantic_similarity],
      sentimentShift: sentiment_shift,
      framing: conn[:framing],
      framingExplanation: conn[:framing_explanation],
      # GDELT (optional)
      actorSummary: conn[:actor_summary],
      eventDescription: conn[:event_description],
      goldsteinScale: conn[:goldstein_scale],
      quadClass: conn[:quad_class],
      # Entity overlap (optional)
      sharedEntities: conn[:shared_entities],
      sharedEntityCount: conn[:shared_entity_count],
      # Route reference
      routeId: conn[:route_id],
      # Perspective
      perspectiveSlug: SourceClassifierService.classify(source.source_name.to_s)[:slug],
      # Article IDs for both points
      articleId: source.id
    }
  end

  def build_article_node(article, center)
    analysis = article.ai_analysis
    {
      id: article.id,
      lat: article.latitude,
      lng: article.longitude,
      headline: article.headline,
      source: article.source_name,
      country: article.country&.name,
      publishedAt: article.published_at&.iso8601,
      threatLevel: analysis&.threat_level,
      sentimentColor: analysis&.sentiment_color || "#6b7280",
      sentimentLabel: analysis&.sentiment_label,
      isCenter: center && article.id == center.id,
      perspectiveSlug: SourceClassifierService.classify(article.source_name.to_s)[:slug],
      size: center && article.id == center.id ? 0.8 : 0.4
    }
  end

  # ──────────────────────────────────────────────────────────────
  # Scoring (veritasThreatScore-derived)
  # ──────────────────────────────────────────────────────────────

  THREAT_LEVEL_SCORES = {
    "CRITICAL"   => 10.0,
    "HIGH"       => 7.5,
    "MODERATE"   => 5.0,
    "LOW"        => 2.5,
    "NEGLIGIBLE" => 1.0
  }.freeze

  def compute_arc_threat_score(source_threat, target_threat, conn)
    s = THREAT_LEVEL_SCORES[source_threat] || 0.0
    t = THREAT_LEVEL_SCORES[target_threat] || 0.0
    threat_context = if s > 0 && t > 0
      (s + t) / 2.0
    elsif s > 0 || t > 0
      [s, t].max
    else
      0.0
    end

    # Boost from connection type diversity
    type_bonus = conn[:connection_types].size > 1 ? 0.5 : 0.0

    # GDELT conflict bonus
    gdelt_bonus = 0.0
    if conn[:goldstein_scale]
      gdelt_bonus = (-conn[:goldstein_scale]).clamp(0.0, 5.0) * 0.3
    end
    if conn[:quad_class].to_i >= 3
      gdelt_bonus += 1.0
    end

    score = (threat_context * 0.6 + type_bonus + gdelt_bonus).clamp(0.0, 10.0).round(1)
    score
  end

  def threat_score_to_color(score)
    if score >= 7
      "#ff4444"
    elsif score >= 5
      "#ff8c00"
    elsif score >= 3
      "#ffd700"
    else
      "#6088a0"
    end
  end

  def build_sentiment_shift(source_label, target_label)
    src = normalize_sentiment(source_label)
    tgt = normalize_sentiment(target_label)
    return nil if src == "Unknown" && tgt == "Unknown"
    "#{src} → #{tgt}"
  end

  def normalize_sentiment(label)
    l = label.to_s.downcase
    return "Positive" if l.include?("positive") || l.include?("bullish")
    return "Negative" if l.include?("negative") || l.include?("hostile")
    return "Neutral" if l.present?
    "Unknown"
  end

  # ──────────────────────────────────────────────────────────────
  # Helpers
  # ──────────────────────────────────────────────────────────────

  def preload_articles(ids)
    Article.where(id: ids)
      .includes(:country, :ai_analysis, :entities)
      .to_a
  end

  def time_range_for(article, window)
    center_time = article.published_at || Time.current
    (center_time - window)..(center_time + window)
  end

  def normalize_actor_pair(actor1, actor2)
    return nil if actor1.blank? && actor2.blank?
    [actor1.to_s.strip.downcase, actor2.to_s.strip.downcase].sort.join("→")
  end

  def empty_result
    { articles: [], arcs: [], meta: { total_connections: 0, rendered_connections: 0, render_limit: RENDER_LIMIT, connection_types: {}, total_articles: 0 } }
  end
end
