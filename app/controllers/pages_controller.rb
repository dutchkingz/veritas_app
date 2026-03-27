class PagesController < ApplicationController
  DEFAULT_ARC_COLOR = "#00f0ff".freeze
  skip_before_action :authenticate_user!, only: [:welcome, :home, :globe_data, :search, :aware, :aware_narration, :narrative_dna, :tribunal, :article_preview, :entity_nexus, :entity_nexus_detail, :article_network]

  def welcome
    redirect_to dashboard_path if user_signed_in?
    # Landing page with login
    # resource and resource_name are needed for Devise form
    @resource = User.new
    @resource_name = :user
    @devise_mapping = Devise.mappings[:user]

    # Top stories for the hero ticker
    @top_stories = Article.includes(:ai_analysis)
                          .where.not(ai_analysis: { threat_level: nil })
                          .order('ai_analysis.threat_level DESC, published_at DESC')
                          .limit(10)
  end

  def aware
    @latest_brief = IntelligenceBrief.complete.latest.first
    @signatures = NarrativeSignature.active.recent.limit(20)
    @top_sources = SourceCredibility.by_grade.limit(20)
    @contradictions = ContradictionLog.recent.limit(10)
    @latest_snapshot = EmbeddingSnapshot.recent.first
    @total_articles = Article.joins(:ai_analysis).where(ai_analyses: { analysis_status: "complete" }).count
    @total_sources = SourceCredibility.count
    @total_sources = Article.distinct.count(:source_name) if @total_sources.zero?
    @confidence_map = AiAnalysis.where(analysis_status: "complete")
                                .where.not(geopolitical_topic: [nil, ""])
                                .group(:geopolitical_topic)
                                .count
                                .sort_by { |_, v| -v }
                                .first(15)

    # Self-narration data
    @total_analyses = AiAnalysis.where(analysis_status: "complete").count
    @total_contradictions = ContradictionLog.count
    @total_briefs = IntelligenceBrief.complete.count
    @total_entities = Entity.count
    @total_entity_mentions = EntityMention.count
    @top_entity = Entity.order(mentions_count: :desc).first
    # If counter cache is 0 (fresh seed), fall back to entity with most articles
    if @top_entity&.mentions_count&.zero?
      @top_entity = Entity.left_joins(:entity_mentions)
                          .group(:id)
                          .order("COUNT(entity_mentions.id) DESC")
                          .first
      @total_entity_mentions = EntityMention.count
    end
    @top_signature = @signatures.first
    @entity_types_breakdown = Entity.group(:entity_type).count

    # System age & learning rate — use published_at so freshly seeded data still shows real span
    earliest = Article.minimum(:published_at) || Article.minimum(:created_at)
    @system_age_hours = earliest ? ((Time.current - earliest) / 1.hour).round : 0
    @articles_per_day = (@total_articles.to_f / [(@system_age_hours / 24.0).ceil, 1].max).round(1)

    # Knowledge gaps
    @under_profiled_sources = SourceCredibility.where("articles_analyzed < ?", 5).limit(10)
    @under_profiled_count = SourceCredibility.where("articles_analyzed < ?", 5).count
    @blind_spot_regions = @latest_brief&.blind_spots&.map { |bs| bs["region"] }&.compact || []
    @low_confidence_topics = @confidence_map.select { |_, count| count < 5 }
    @low_confidence_count = @low_confidence_topics.size

    # System confidence gauge
    total_coverage = @confidence_map.sum { |_, count| count }
    max_possible = [@confidence_map.size * 50, 1].max
    @system_confidence = ((total_coverage.to_f / max_possible) * 100).clamp(0, 100).round

    # Signature growth status
    @signature_statuses = @signatures.to_h { |sig|
      status = sig.last_seen_at > 6.hours.ago ? "RISING" : sig.last_seen_at > 48.hours.ago ? "STABLE" : "DORMANT"
      [sig.id, status]
    }
  end

  # GET /api/aware_narration — ElevenLabs TTS audio of the VERITAS self-narration
  def aware_narration
    narration_text = build_aware_narration
    cache_key = "aware_narration/#{Digest::MD5.hexdigest(narration_text)}"

    audio = Rails.cache.fetch(cache_key, expires_in: 1.hour) do
      ElevenLabsService.new(text: narration_text).call
    end

    if audio
      send_data audio, type: "audio/mpeg", disposition: "inline"
    else
      head :service_unavailable
    end
  end

  def home
    # Hot articles: surface the most geopolitically interesting, best-analyzed
    # articles. Prioritize by threat severity, narrative richness, then suspicion.
    # Exclude GDELT articles that still have placeholder headlines (not yet scraped).
    #
    # NOTE: threat_level is a string (CRITICAL/HIGH/MODERATE/LOW/NEGLIGIBLE),
    # NOT a number — alphabetical sort puts NEGLIGIBLE first! Use CASE WHEN.
    threat_order = Arel.sql(<<~SQL.squish)
      CASE ai_analyses.threat_level
        WHEN 'CRITICAL'   THEN 5
        WHEN 'HIGH'       THEN 4
        WHEN 'MODERATE'   THEN 3
        WHEN 'LOW'        THEN 2
        WHEN 'NEGLIGIBLE' THEN 1
        ELSE 3
      END DESC,
      (SELECT COUNT(*) FROM narrative_arcs WHERE narrative_arcs.article_id = articles.id) DESC,
      ai_analyses.trust_score ASC,
      articles.published_at DESC
    SQL

    @hot_articles = Article
      .includes(:country, :region, :ai_analysis, narrative_arcs: :narrative_routes)
      .joins(:ai_analysis)
      .where.not(ai_analyses: { threat_level: nil })
      .where.not("headline LIKE '%— GDELT'")
      .order(threat_order)
      .limit(15)
    
    # Fallback: all articles ordered by date (if not enough hot articles)
    @articles = Article.includes(:country, :region).order(published_at: :desc).limit(50)
    @signal_count        = Article.count
    @regions             = Region.order(:name)
    @perspective_filters = PerspectiveFilter.order(:name)
    @timeline_min        = Article.minimum(:published_at)&.to_i || Time.now.to_i
    @timeline_max        = Article.maximum(:published_at)&.to_i || Time.now.to_i

    # Latest completed IntelligenceReport per region — keyed by region_id.
    # Used to show verdict badge + dossier link for all users in the sidebar.
    @latest_reports = IntelligenceReport
      .where(status: "completed")
      .order(created_at: :desc)
      .group_by(&:region_id)
      .transform_values(&:first)

    @veritas_mode = VeritasMode.current
    @api_calls_remaining = VeritasMode.api_calls_remaining
  end

  # GET /api/globe_data — JSON feed for Globe.gl
  #
  # Perspective filtering is now CLIENT-SIDE (Globe.gl color callbacks).
  # The server no longer hides non-perspective articles — it tags each point/arc
  # with a perspectiveSlug so the JS can dim them without re-fetching.
  #
  # Params:
  #   to             — timestamp ceiling (timeline scrubber)
  #   view           — "segments" | "arcs"
  #   search_query   — text or semantic search
  #   topic          — keyword topic filter (NATO, BRICS, etc.) — server-side ILIKE
  def globe_data
    to_time      = params[:to].present? ? Time.at(params[:to].to_i) : nil
    view_mode    = params[:view] || "arcs"
    search_query = params[:search_query]
    topic        = params[:topic].presence

    # Cache key incorporates all query params + latest article timestamp.
    # Auto-invalidates when any article is created/updated.
    # Search queries skip the cache (semantic search is already fast + personalised).
    cache_key = if search_query.blank?
                  latest = Article.maximum(:updated_at)&.to_i
                  "globe_data:#{to_time&.to_i}:#{view_mode}:#{topic}:#{latest}"
                end

    if cache_key
      cached = Rails.cache.read(cache_key)
      if cached
        return render json: cached
      end
    end

    scope  = Article.includes(:country, :region, :ai_analysis)
    scope  = scope.where("published_at <= ?", to_time) if to_time
    scope  = scope.order(published_at: :desc)

    # Topic filter — ILIKE on headline (works in both demo and live mode)
    if topic.present?
      scope = scope.where("headline ILIKE ?", "%#{topic}%")
                   .or(scope.where("content ILIKE ?", "%#{topic}%"))
    end

    # Search filter
    if search_query.present?
      if VeritasMode.demo?
        scope = scope.where("headline ILIKE ?", "%#{search_query}%")
                     .or(scope.where("content ILIKE ?", "%#{search_query}%"))
      else
        begin
          vector = OpenRouterClient.new.embed(search_query)
          if vector.present?
            similar_ids = Article.nearest_neighbors(:embedding, vector, distance: "cosine")
                                 .limit(100)
                                 .pluck(:id)
            scope = scope.where(id: similar_ids)
          end
        rescue StandardError => e
          Rails.logger.warn "[globe_data] Semantic search failed: #{e.message}"
          scope = scope.where("headline ILIKE ?", "%#{search_query}%")
                       .or(scope.where("content ILIKE ?", "%#{search_query}%"))
        end
      end
    end

    # All articles — perspective filtering is client-side via Globe.gl color callbacks
    filtered_articles = scope.limit(250).to_a

    points = filtered_articles.first(200).filter_map do |a|
      next if a.latitude.blank? || a.longitude.blank?
      next if null_island?(a.latitude, a.longitude)
      next unless valid_coordinates?(a.latitude, a.longitude)

      sentiment_color  = a.ai_analysis&.sentiment_color || "#00f0ff"
      perspective_slug = SourceClassifierService.classify(a.source_name)[:slug]
      {
        id:              a.id,
        lat:             a.latitude,
        lng:             a.longitude,
        size:            0.4,
        color:           sentiment_color,
        headline:        a.headline,
        source:          a.source_name,
        perspectiveSlug: perspective_slug
      }
    end

    routes = []
    arcs = if view_mode == "segments"
             route_payload = build_route_segments(filtered_articles, nil, to_time)
             routes = route_payload[:routes]
             # If default view (no search/topic) returns few segments, inject top narratives
             if route_payload[:segments].size < 5 && search_query.blank? && topic.blank?
               top_payload = build_top_narrative_segments(to_time)
               routes = (routes + top_payload[:routes]).uniq { |r| r[:id] }
               all_segments = (route_payload[:segments] + top_payload[:segments]).uniq { |s| s[:id] }
               all_segments.any? ? all_segments : build_globe_arcs(filtered_articles, nil, to_time)
             else
               route_payload[:segments].any? ? route_payload[:segments] : build_globe_arcs(filtered_articles, nil, to_time)
             end
           else
             build_globe_arcs(filtered_articles, nil, to_time)
           end

    # Dynamic regions: countries that actually have articles
    # Use country coordinates (hardcoded for top countries)
    country_coordinates = {
      'UKR' => [48.3794, 31.1656],   # Ukraine
      'DEU' => [51.1657, 10.4515],   # Germany
      'CHN' => [35.8617, 104.1954],  # China
      'ISR' => [31.0461, 34.8516],   # Israel
      'USA' => [37.0902, -95.7129],  # United States
      'RUS' => [61.5240, 105.3188], # Russia
      'FRA' => [46.2276, 2.2137],    # France
      'GBR' => [55.3781, -3.4360],   # United Kingdom
      'IRN' => [32.4279, 53.6880],   # Iran
      'IND' => [20.5937, 78.9629]    # India
    }
    
    countries_with_articles = Country
      .joins(:articles)
      .select('countries.*, COUNT(articles.id) as article_count')
      .group('countries.id')
      .having('COUNT(articles.id) > 0')
      .order('article_count DESC')
      .limit(25)  # Top 25 countries by article count
    
    regions = countries_with_articles.map do |c|
      article_count = c.attributes['article_count'].to_i
      threat = [article_count, 10].min
      coords = country_coordinates[c.iso_code] || [0.0, 0.0]

      {
        lat:    coords[0],
        lng:    coords[1],
        name:   c.name,
        threat: threat,
        radius: article_count > 0 ? [Math.sqrt(article_count) * 0.25, 1.5].min : 0.3,
        articleCount: article_count
      }
    end

    # Heatmap cluster summaries — per-country intel for thermal tooltip
    heatmap_clusters = countries_with_articles.first(15).map do |c|
      coords = country_coordinates[c.iso_code] || [0.0, 0.0]
      country_articles = filtered_articles.select { |a| a.country_id == c.id }
      avg_threat = if country_articles.any?
                     threats = country_articles.filter_map { |a| a.ai_analysis&.threat_level&.to_i }
                     threats.any? ? (threats.sum.to_f / threats.size).round(1) : 0
                   else
                     0
                   end
      top_headlines = country_articles
        .sort_by { |a| -(a.ai_analysis&.threat_level.to_i) }
        .first(3)
        .map { |a| { headline: a.headline.truncate(80), source: a.source_name } }

      {
        lat:          coords[0],
        lng:          coords[1],
        name:         c.name,
        iso:          c.iso_code,
        articleCount: c.attributes['article_count'].to_i,
        avgThreat:    avg_threat,
        topHeadlines: top_headlines
      }
    end

    # Heatmap data: one entry per geolocated article, weight = threat intensity
    # Base weight 0.4 ensures even unevaluated articles show up on the thermal layer.
    heatmap = filtered_articles.first(200).filter_map do |a|
      next if a.latitude.blank? || a.longitude.blank?
      next if null_island?(a.latitude, a.longitude)

      threat = a.ai_analysis&.threat_level.to_f   # 0–10 (nil → 0)
      trust  = a.ai_analysis&.trust_score.to_f    # 0–100 (nil → 0, treated as unknown)

      # Articles without AI analysis get a base heat of 0.4 (visible but not alarming).
      # Articles with analysis: high threat + low trust → hot.
      if a.ai_analysis.nil?
        weight = 0.4
      else
        weight = ((threat / 10.0) * 0.65 + ((100.0 - trust) / 100.0) * 0.35).clamp(0.2, 1.0)
      end

      { lat: a.latitude, lng: a.longitude, weight: weight }
    end

    payload = {
      points: points, arcs: arcs, routes: routes, regions: regions,
      heatmap: heatmap, heatmapClusters: heatmap_clusters,
      mode: VeritasMode.current
    }

    Rails.cache.write(cache_key, payload, expires_in: 5.minutes) if cache_key

    render json: payload
  end

  # GET /api/article_preview/:article_id — Lightweight article card for DNA node click
  def article_preview
    article = Article.includes(:ai_analysis, :country).find_by(id: params[:article_id])
    return render json: { error: "Not found" }, status: :not_found unless article

    snippet = if article.content.present?
                ActionController::Base.helpers.strip_tags(article.content)
                                      .gsub(/\s+/, " ").strip.first(280)
              else
                article.raw_data&.dig("description").to_s.first(280)
              end

    render json: {
      id:              article.id,
      headline:        article.headline,
      source:          article.source_name,
      country:         article.country&.name,
      published_at:    article.published_at&.iso8601,
      snippet:         snippet.presence || "No content available.",
      threat_level:    article.ai_analysis&.threat_level,
      sentiment_color: article.ai_analysis&.sentiment_color || "#6b7280"
    }
  end

  # GET /api/tribunal/:article_id — Agent debate JSON for War Room Tribunal
  def tribunal
    article = Article.includes(:ai_analysis, :country).find_by(id: params[:article_id])
    return render json: { error: "Not found" }, status: :not_found unless article

    data = TribunalService.new(article).call
    render json: data
  end

  # GET /api/entity_nexus — Force-directed graph JSON for Entity Nexus panel
  def entity_nexus
    service = EntityNexusService.new(
      min_mentions: (params[:min_mentions] || 1).to_i,
      entity_type:  params[:entity_type].presence,
      article_id:   params[:article_id].presence
    )
    render json: service.call
  end

  # GET /api/entity_nexus/:entity_id — Detail JSON for a single entity node
  def entity_nexus_detail
    entity = Entity.find_by(id: params[:entity_id])
    return render json: { error: "Not found" }, status: :not_found unless entity

    articles = entity.articles
      .includes(:ai_analysis, :country)
      .order(published_at: :desc)
      .limit(8)

    # Top connected entities via raw SQL — avoids COUNT(*) pluck issues
    article_ids = entity.article_ids.first(50)
    connected = if article_ids.any?
      rows = ActiveRecord::Base.connection.execute(<<~SQL)
        SELECT e.id, e.name, e.entity_type, COUNT(*) AS shared_count
        FROM entity_mentions em
        JOIN entities e ON e.id = em.entity_id
        WHERE em.article_id IN (#{article_ids.map(&:to_i).join(',')})
          AND em.entity_id != #{entity.id.to_i}
        GROUP BY e.id, e.name, e.entity_type
        ORDER BY shared_count DESC
        LIMIT 5
      SQL
      rows.map { |r| { id: r["id"].to_i, name: r["name"], entity_type: r["entity_type"], shared_articles: r["shared_count"].to_i } }
    else
      []
    end

    sentiment_breakdown = compute_sentiment_breakdown(entity)
    max_mentions = Entity.maximum(:mentions_count).to_f
    vol_score    = max_mentions > 0 ? (entity.mentions_count.to_f / max_mentions) : 0
    power_index  = (vol_score * 60).round  # simplified — full calc needs region/threat data

    render json: {
      id:                 entity.id,
      name:               entity.name,
      entity_type:        entity.entity_type,
      color:              entity.color,
      mentions_count:     entity.mentions_count,
      power_index:        power_index,
      first_seen_at:      entity.first_seen_at&.iso8601,
      connected_entities: connected,
      articles: articles.map { |a| {
        id:              a.id,
        headline:        a.headline,
        source_name:     a.source_name,
        published_at:    a.published_at&.iso8601,
        country:         a.country&.name,
        threat_level:    a.ai_analysis&.threat_level,
        sentiment_color: a.ai_analysis&.sentiment_color || "#6b7280"
      }},
      sentiment: sentiment_breakdown
    }
  rescue StandardError => e
    Rails.logger.error "[EntityNexusDetail] ##{params[:entity_id]}: #{e.class} #{e.message}"
    render json: { error: "Internal error" }, status: :internal_server_error
  end

  # GET /api/article_network/:article_id — Network graph around an article
  #
  # Params:
  #   depth       — 1 or 2 (default 2)
  #   time_window — hours (default 48)
  #   mode        — "network" (single article) or "global" (top threat articles)
  def article_network
    if params[:article_id] == "global"
      # Global View: top threat articles + connections between them
      top_articles = Article
        .includes(:country, :ai_analysis, :entities)
        .joins(:ai_analysis)
        .where.not(ai_analyses: { threat_level: [nil, "NEGLIGIBLE", "LOW"] })
        .where.not(latitude: nil)
        .where.not(longitude: nil)
        .order(Arel.sql(<<~SQL.squish))
          CASE ai_analyses.threat_level
            WHEN 'CRITICAL' THEN 5 WHEN 'HIGH' THEN 4 WHEN 'MODERATE' THEN 3 ELSE 1
          END DESC, articles.published_at DESC
        SQL
        .limit(25)
        .to_a

      data = ArticleNetworkService.new.connections_between(top_articles, time_window: 72.hours)
      return render json: data
    end

    # Search mode: find articles by query, then compute network connections
    if params[:article_id] == "search"
      search_query = params[:search_query].to_s.strip
      return render json: { articles: [], arcs: [], meta: { total_connections: 0 } } if search_query.blank?

      search_articles = find_articles_for_network_search(search_query)
      return render json: { articles: [], arcs: [], meta: { total_connections: 0 } } if search_articles.empty?

      data = ArticleNetworkService.new.connections_between(search_articles, time_window: 72.hours)

      # Cap arcs at 25 for search (already sorted by strength from service)
      data[:arcs] = data[:arcs].first(25) if data[:arcs]
      data[:meta][:rendered_connections] = data[:arcs]&.size || 0

      return render json: data
    end

    article = Article.find_by(id: params[:article_id])
    return render json: { error: "Not found" }, status: :not_found unless article

    depth = (params[:depth] || 2).to_i.clamp(1, 3)
    time_window = (params[:time_window] || 48).to_i.hours

    data = ArticleNetworkService.new.network_for_article(article, depth: depth, time_window: time_window)
    render json: data
  end

  # GET /api/narrative_dna/:article_id — Graph JSON for Narrative DNA panel
  def narrative_dna
    article = Article.find_by(id: params[:article_id])
    return render json: { error: "Not found" }, status: :not_found unless article

    data = NarrativeDnaService.new(article).call
    render json: data
  end

  def search
    @query = params[:q]

    if @query.present?
      if VeritasMode.demo?
        # Demo mode: text search only — zero API calls
        @results = Article.where("headline ILIKE ?", "%#{@query}%")
                          .or(Article.where("content ILIKE ?", "%#{@query}%"))
                          .preload(:country, :region, :ai_analysis)
                          .order(published_at: :desc)
                          .limit(20)
                          .to_a
      else
        begin
          vector = OpenRouterClient.new.embed(@query)

          if vector.present?
            @results = Article.nearest_neighbors(:embedding, vector, distance: "cosine")
                              .preload(:country, :region, :ai_analysis)
                              .limit(20)
                              .to_a
          else
            @results = []
            flash.now[:alert] = "Failed to generate semantic search vector."
          end
        rescue StandardError => e
          @results = []
          flash.now[:alert] = "Search is temporarily unavailable."
          Rails.logger.error "[SEMANTIC SEARCH] Error: #{e.message}"
        end
      end
    else
      @results = []
    end
  end

  private

  def build_aware_narration
    total_articles = Article.joins(:ai_analysis).where(ai_analyses: { analysis_status: "complete" }).count
    total_sources  = SourceCredibility.count
    total_sources  = Article.distinct.count(:source_name) if total_sources.zero?
    signatures     = NarrativeSignature.active.recent.limit(5)
    top_signature  = signatures.first
    top_entity     = Entity.order(mentions_count: :desc).first
    total_entities = Entity.count
    total_contradictions = ContradictionLog.count
    latest_brief   = IntelligenceBrief.complete.latest.first

    earliest = Article.minimum(:published_at) || Article.minimum(:created_at)
    system_age_hours = earliest ? ((Time.current - earliest) / 1.hour).round : 0

    blind_spots = latest_brief&.blind_spots&.map { |bs| bs["region"] }&.compact || []

    parts = []
    parts << "I have processed... #{total_articles} articles... across #{total_sources} sources... in #{system_age_hours} hours of operation."
    parts << "I recognize... #{signatures.size} recurring narrative patterns." if signatures.any?
    parts << "My strongest signal... is #{top_signature.label}... #{top_signature.match_count} articles... and growing." if top_signature
    if top_entity
      mention_count = top_entity.mentions_count.to_i > 0 ? top_entity.mentions_count : EntityMention.where(entity: top_entity).count
      if mention_count > 0
        parts << "I track #{total_entities} entities... #{top_entity.name}... appears most frequently... across #{mention_count} mentions."
      else
        parts << "I track #{total_entities} entities across my intelligence corpus."
      end
    end
    parts << "I have caught... #{total_contradictions} contradictions... between sources." if total_contradictions > 0
    parts << "I have #{blind_spots.size} blind spots... Regions I cannot yet... adequately cover." if blind_spots.any?
    parts << "My last intelligence assessment... was #{ActionController::Base.helpers.time_ago_in_words(latest_brief.created_at)} ago." if latest_brief
    parts.join(" ... ")
  end

  def compute_sentiment_breakdown(entity)
    labels = entity.articles
      .joins(:ai_analysis)
      .where.not(ai_analyses: { sentiment_label: nil })
      .pluck("ai_analyses.sentiment_label")
      .map { |l| l.to_s.downcase }

    total = labels.size.to_f
    return { positive: 0, neutral: 0, negative: 0 } if total.zero?

    positive = labels.count { |l| l.include?("positive") || l.include?("bullish") }
    negative = labels.count { |l| l.include?("negative") || l.include?("bearish") || l.include?("hostile") }
    neutral  = labels.size - positive - negative

    {
      positive: (positive / total * 100).round,
      neutral:  (neutral  / total * 100).round,
      negative: (negative / total * 100).round
    }
  end

  # Search helper for article_network search mode.
  # Mirrors the search logic from globe_data (demo: ILIKE, live: pgvector).
  def find_articles_for_network_search(search_query)
    scope = Article.includes(:country, :ai_analysis, :entities)
                   .where.not(latitude: nil)
                   .where.not(longitude: nil)

    if VeritasMode.demo?
      scope = scope.where("headline ILIKE ?", "%#{search_query}%")
                   .or(scope.where("content ILIKE ?", "%#{search_query}%"))
    else
      begin
        vector = OpenRouterClient.new.embed(search_query)
        if vector.present?
          similar_ids = Article.nearest_neighbors(:embedding, vector, distance: "cosine")
                               .limit(50)
                               .pluck(:id)
          scope = scope.where(id: similar_ids)
        else
          scope = scope.where("headline ILIKE ?", "%#{search_query}%")
                       .or(scope.where("content ILIKE ?", "%#{search_query}%"))
        end
      rescue StandardError => e
        Rails.logger.warn "[article_network/search] Semantic search failed: #{e.message}"
        scope = scope.where("headline ILIKE ?", "%#{search_query}%")
                     .or(scope.where("content ILIKE ?", "%#{search_query}%"))
      end
    end

    scope.order(published_at: :desc).limit(50).to_a
  end

  def build_route_segments(filtered_articles, perspective, to_time)
    filtered_ids = filtered_articles.map(&:id)

    # Resolve arc IDs first — avoids JOIN ambiguity from combines includes+joins
    arc_ids = NarrativeArc.where(article_id: filtered_ids).pluck(:id)

    # Fetch narrative routes restricted to the filtered arc set
    scope = NarrativeRoute
      .where(narrative_arc_id: arc_ids)
      .joins(narrative_arc: :article)
      .includes(narrative_arc: { article: :ai_analysis })
      .where.not(hops: nil)
      .order("narrative_routes.created_at DESC")

    # Filter by timestamp if provided
    if to_time
      scope = scope.where("articles.published_at <= ?", to_time)
    end

    # Filter by perspective if provided
    if perspective
      scope = scope.select do |route|
        perspective.matches_source?(route.narrative_arc.article.source_name)
      end
    else
      scope = scope.limit(100)
    end

    # Score each route by avg hop confidence (our best proxy for semantic strength),
    # rank them, and assign visual tiers: top 5 = primary, next 10 = secondary, rest dropped.
    # This eliminates spaghetti: max 15 routes × max 8 hops = 120 segments absolute ceiling.
    scored_routes = scope.filter_map do |route|
      route_data = route.as_globe_data
      next unless route_data[:segments] && route_data[:segments].any?

      confidences = route.hops.filter_map { |h| h['confidence_score']&.to_f }
      strength    = confidences.any? ? (confidences.sum / confidences.size.to_f) : 0.5

      { route_data: route_data, strength: strength, route: route,
        article: route.narrative_arc.article }
    end

    scored_routes.sort_by! { |r| -r[:strength] }

    segments = []
    routes = []

    scored_routes.first(15).each_with_index do |r, index|
      tier     = index < 5 ? 1 : 2
      strength = r[:strength].round(3)
      route    = r[:route]
      route_data = route.as_journey_data

      routes << route_data.merge(
        strength: strength,
        tier: tier
      )

      route_data[:segments].each do |segment|
        next if degenerate_arc?(segment)
        segments << segment.merge(
          strength: strength,
          tier: tier
        )
      end
    end

    { segments: segments, routes: routes }
  end

  # Top narrative routes by manipulation score — used to populate the default homepage view
  # so users see the most interesting intelligence immediately rather than an empty globe.
  def build_top_narrative_segments(to_time)
    scope = NarrativeRoute
      .joins(narrative_arc: :article)
      .includes(narrative_arc: { article: :ai_analysis })
      .where.not(hops: nil)
      .where("narrative_routes.total_hops >= ?", 2)
      .where("narrative_routes.created_at >= ?", 7.days.ago)
      .order(manipulation_score: :desc, total_reach_countries: :desc)

    scope = scope.where("articles.published_at <= ?", to_time) if to_time

    segments = []
    routes = []

    scope.limit(25).each_with_index do |route, index|
      route_data = route.as_journey_data
      next unless route_data[:segments]&.any?

      tier = index < 5 ? 1 : 2
      confidences = route.hops.filter_map { |h| h["confidence_score"]&.to_f }
      strength = confidences.any? ? (confidences.sum / confidences.size.to_f).round(3) : 0.5

      routes << route_data.merge(strength: strength, tier: tier)

      route_data[:segments].each do |segment|
        next if degenerate_arc?(segment)
        segments << segment.merge(strength: strength, tier: tier)
      end
    end

    { segments: segments, routes: routes }
  end

  def build_globe_arcs(filtered_articles, perspective, to_time)
    filtered_ids = filtered_articles.map(&:id)

    # 1. Flow arcs (auto-generated from article sequence)
    # DISABLED: These create confusion with real narrative paths.
    # flow_arcs = build_article_flow_arcs(filtered_articles, perspective)

    # 2. Database arcs (seeded NarrativeArcs) — restricted to filtered article set
    scope = NarrativeArc.includes(article: :ai_analysis).order(:id)
    scope = scope.where(article_id: filtered_ids) if filtered_ids.any?
    scope = scope.joins(:article).where("articles.published_at <= ?", to_time) if to_time

    db_arcs = if perspective
                scope.joins(:article).select { |arc| perspective.matches_source?(arc.article.source_name) }
                     .map { |arc| serialize_arc(arc, perspective.color).merge(isNarrative: true) }
              else
                scope.limit(50).map { |arc| serialize_arc(arc).merge(isNarrative: true) }
              end

    # Return only real narrative arcs to keep the intelligence layer focused.
    # Filter degenerate arcs (same start/end point = hedgehog needles)
    db_arcs.reject { |arc| degenerate_arc?(arc) }.first(100)
  end

  def build_article_flow_arcs(filtered_articles, perspective)
    # This method is now unused by default to avoid visual 'clutter'
    # that users misinterpret as broken narrative links.
    candidates = filtered_articles
      .select { |article| article.country.present? && article.latitude.present? && article.longitude.present? }
      .sort_by { |article| article.published_at || Time.at(0) }
      .last(80)

    candidates.each_cons(2).filter_map do |origin, target|
      next if origin.country_id == target.country_id

      {
        startLat:      origin.latitude,
        startLng:      origin.longitude,
        endLat:        target.latitude,
        endLng:        target.longitude,
        color:         [arc_start_color_for(origin, perspective), arc_end_color_for(origin, target, perspective)],
        articleId:     origin.id,
        headline:      origin.headline,
        source:        origin.source_name,
        originCountry: origin.country.name,
        targetCountry: target.country.name
      }
    end.first(50)
  end

  def serialize_arc(arc, fallback_color = nil)
    base_color = fallback_color || arc.article&.ai_analysis&.sentiment_color || arc.arc_color || DEFAULT_ARC_COLOR

    {
      startLat:        arc.origin_lat,
      startLng:        arc.origin_lng,
      endLat:          arc.target_lat,
      endLng:          arc.target_lng,
      color:           [base_color, brighten_hex(base_color, 0.18)],
      articleId:       arc.article_id,
      headline:        arc.article&.headline,
      source:          arc.article&.source_name,
      perspectiveSlug: SourceClassifierService.classify(arc.article&.source_name.to_s)[:slug],
      originCountry:   arc.origin_country,
      targetCountry:   arc.target_country
    }
  end

  def arc_start_color_for(article, perspective)
    semantic_color_for(article) || perspective&.color || threat_color_for(article.region&.threat_level) || DEFAULT_ARC_COLOR
  end

  def arc_end_color_for(origin_article, target_article, perspective)
    end_color = semantic_color_for(target_article) ||
                semantic_color_for(origin_article) ||
                perspective&.color ||
                threat_color_for(target_article.region&.threat_level) ||
                threat_color_for(origin_article.region&.threat_level) ||
                DEFAULT_ARC_COLOR

    brighten_hex(end_color, 0.18)
  end

  def semantic_color_for(article)
    analysis = article.ai_analysis
    return analysis.sentiment_color if analysis&.sentiment_color.present?

    threat_color_for(analysis&.threat_level || article.region&.threat_level)
  end

  def threat_color_for(threat)
    case threat.to_s.upcase
    when "3", "CRITICAL" then "#ef4444"
    when "2", "HIGH", "MODERATE" then "#f59e0b"
    when "1", "LOW" then "#22c55e"
    when "0", "NEGLIGIBLE" then "#38bdf8"
    else
      nil
    end
  end

  # Returns true for arcs where start ≈ end (hedgehog needles / spikes).
  def degenerate_arc?(arc)
    s_lat = arc[:startLat]
    s_lng = arc[:startLng]
    e_lat = arc[:endLat]
    e_lng = arc[:endLng]

    # Any nil coordinate = degenerate
    return true if [s_lat, s_lng, e_lat, e_lng].any?(&:nil?)

    # Out-of-range coordinates (GDELT parsing bug) = degenerate
    return true unless valid_coordinates?(s_lat, s_lng) && valid_coordinates?(e_lat, e_lng)

    return true if null_island?(s_lat, s_lng) || null_island?(e_lat, e_lng)

    # Too close (within 2°) = spike/needle regardless of country
    lat_diff = (s_lat.to_f - e_lat.to_f).abs
    lng_diff = (s_lng.to_f - e_lng.to_f).abs
    return true if lat_diff < 2.0 && lng_diff < 2.0

    false
  end

  def null_island?(lat, lng)
    lat.to_f.abs < 1.0 && lng.to_f.abs < 1.0
  end

  def valid_coordinates?(lat, lng)
    lat.to_f.between?(-90.0, 90.0) && lng.to_f.between?(-180.0, 180.0)
  end

  def brighten_hex(hex_color, factor)
    hex = hex_color.to_s.delete_prefix("#")
    return DEFAULT_ARC_COLOR unless hex.match?(/\A[\da-fA-F]{6}\z/)

    channels = hex.scan(/../).map { |pair| pair.to_i(16) }
    brightened = channels.map do |channel|
      (channel + ((255 - channel) * factor)).round.clamp(0, 255)
    end

    "##{brightened.map { |value| value.to_s(16).rjust(2, "0") }.join}"
  end
end
