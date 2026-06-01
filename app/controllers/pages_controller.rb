class PagesController < ApplicationController
  include GeoValidation
  include ArcColorHelper

  skip_before_action :authenticate_user!, only: [:welcome, :home, :globe_data, :search, :aware, :aware_narration, :narrative_dna, :tribunal, :article_preview, :entity_nexus, :entity_nexus_detail, :article_network, :feed_articles]

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
    # Progressive time window: prefer recent articles, widen if too few
    hot_base = Article
      .includes(:country, :region, :ai_analysis, narrative_arcs: :narrative_routes)
      .joins(:ai_analysis)
      .where.not(ai_analyses: { threat_level: nil })
      .where.not("headline LIKE '%— GDELT'")

    # Hot articles: threat-ranked, all of them (capped at 200)
    @hot_articles = hot_base.threat_ordered.limit(200)

    # All articles for "Recent" / "All" mode (newest ingested first, capped at 200)
    @recent_articles = hot_base.order(fetched_at: :desc).limit(200)

    # Fallback: all articles ordered by ingestion time
    @articles = Article.includes(:country, :region).order(fetched_at: :desc).limit(50)
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
    search_query = params[:search_query]
    topic        = params[:topic].presence

    cache_key = if search_query.blank?
                  latest = Article.maximum(:updated_at)&.to_i
                  "globe_data:#{to_time&.to_i}:#{params[:view]}:#{topic}:#{latest}"
                end

    if cache_key
      cached = Rails.cache.read(cache_key)
      return render(json: cached) if cached
    end

    payload = GlobeDataService.new(
      to_time: to_time,
      view_mode: params[:view] || "arcs",
      search_query: search_query,
      topic: topic
    ).call

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

    render json: EntityNexusDetailService.new(entity).call
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
        .threat_ordered
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
      scope = Article.preload(:country, :region, :ai_analysis).order(published_at: :desc)
      @results = SearchService.new(@query, scope: scope, limit: 20).call.to_a
    else
      @results = []
    end
  end

  # GET /api/feed_articles?mode=hot|recent|all&page=1
  def feed_articles
    page = [params[:page].to_i, 1].max
    per_page = 15
    offset = (page - 1) * per_page
    mode = params[:mode] || "hot"

    base = Article
      .includes(:country, :region, :ai_analysis, narrative_arcs: :narrative_routes)
      .joins(:ai_analysis)
      .where.not(ai_analyses: { threat_level: nil })
      .where.not("headline LIKE '%— GDELT'")

    articles = case mode
    when "hot"
      base.threat_ordered
    when "recent"
      base.order(fetched_at: :desc)
    when "all"
      base.order(fetched_at: :desc)
    end

    total = articles.count(:all)
    articles = articles.offset(offset).limit(per_page)

    html = articles.map { |a| render_to_string(partial: "articles/sidebar_item", locals: { article: a }) }.join

    render json: {
      html: html,
      page: page,
      total: total,
      has_more: (offset + per_page) < total
    }
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

  def find_articles_for_network_search(search_query)
    scope = Article.includes(:country, :ai_analysis, :entities)
                   .where.not(latitude: nil)
                   .where.not(longitude: nil)

    SearchService.new(search_query, scope: scope, limit: 50).call
                 .order(published_at: :desc)
                 .limit(50)
                 .to_a
  end

end
