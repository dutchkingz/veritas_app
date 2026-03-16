class PagesController < ApplicationController
  DEFAULT_ARC_COLOR = "#00f0ff".freeze
  skip_before_action :authenticate_user!, only: [:home, :globe_data, :search]

  def home
    # Hot articles: highest threat level first, then trust score (lower = more suspicious)
    @hot_articles = Article
      .includes(:country, :region, :ai_analysis)
      .where.not(ai_analysis: { threat_level: nil })
      .order('ai_analysis.threat_level DESC, ai_analysis.trust_score ASC, articles.published_at DESC')
      .limit(15)
    
    # Fallback: all articles ordered by date (if not enough hot articles)
    @articles = Article.includes(:country, :region).order(published_at: :desc).limit(50)
    @signal_count        = Article.count
    @regions             = Region.order(:name)
    @perspective_filters = PerspectiveFilter.order(:name)
    @timeline_min        = Article.minimum(:published_at)&.to_i || Time.now.to_i
    @timeline_max        = Article.maximum(:published_at)&.to_i || Time.now.to_i
  end

  # GET /api/globe_data — JSON feed for Globe.gl
  def globe_data
    perspective = PerspectiveFilter.find_by(id: params[:perspective_id])
    to_time     = params[:to].present? ? Time.at(params[:to].to_i) : nil
    view_mode   = params[:view] || "arcs"  # arcs | segments
    search_query = params[:search_query]

    scope  = Article.includes(:country, :region, :ai_analysis)
    scope  = scope.where("published_at <= ?", to_time) if to_time
    scope  = scope.order(published_at: :desc)

    # Filter by search query if provided
    if search_query.present?
      # Use pgvector similarity search for semantic matching
      begin
        vector = OpenRouterClient.new.embed(search_query)
        if vector.present?
          # Get semantically similar articles
          similar_ids = Article.nearest_neighbors(:embedding, vector, distance: "cosine")
                               .limit(100)
                               .pluck(:id)
          scope = scope.where(id: similar_ids)
        end
      rescue StandardError => e
        Rails.logger.warn "[globe_data] Semantic search failed: #{e.message}"
        # Fallback to text search
        scope = scope.where("headline ILIKE ?", "%#{search_query}%")
                     .or(scope.where("content ILIKE ?", "%#{search_query}%"))
      end
    end

    filtered_articles = scope.limit(250).select do |article|
      perspective.nil? || perspective.matches_source?(article.source_name)
    end

    points = filtered_articles.first(200).filter_map do |a|
      next if a.latitude.blank? || a.longitude.blank?

      next if perspective && !perspective.matches_source?(a.source_name)
      sentiment_color = a.ai_analysis&.sentiment_color || "#00f0ff"
      {
        id:       a.id,
        lat:      a.latitude,
        lng:      a.longitude,
        size:     0.4,
        color:    sentiment_color,
        headline: a.headline,
        source:   a.source_name
      }
    end

    arcs = if view_mode == "segments"
             segments = build_route_segments(filtered_articles, perspective, to_time)
             segments.any? ? segments : build_globe_arcs(filtered_articles, perspective, to_time)
           else
             build_globe_arcs(filtered_articles, perspective, to_time)
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

    render json: { points: points, arcs: arcs, regions: regions }
  end

  def search
    @query = params[:q]
    
    if @query.present?
      begin
        # 1. Embed the user's search query into a vector
        vector = OpenRouterClient.new.embed(@query)
        
        if vector.present?
          # nearest_neighbors must be called FIRST.
          # Use .preload (not .includes) — includes triggers a COUNT subquery that
          # conflicts with pgvector's AS neighbor_distance alias → SQL crash.
          # Materialize with .to_a so the view never fires extra COUNT queries on the relation.
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
    else
      @results = []
    end
  end

  private

  def build_route_segments(filtered_articles, perspective, to_time)
    # Fetch narrative routes with their hops, filtered by time and perspective
    scope = NarrativeRoute.joins(narrative_arc: :article)
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

    segments = []
    
    scope.each do |route|
      route_data = route.as_globe_data
      next unless route_data[:segments] && route_data[:segments].any?
      
      article = route.narrative_arc.article
      route_metadata = {
        routeId: route.id,
        routeName: route.name,
        arcId: route.narrative_arc_id,
        manipulationScore: route.manipulation_score,
        amplificationScore: route.amplification_score,
        totalHops: route.total_hops,
        isComplete: route.is_complete,
        articleId: article&.id,
        headline: article&.headline,
        source: article&.source_name,
        originCountry: route.narrative_arc.origin_country,
        targetCountry: route.narrative_arc.target_country
      }
      
      route_data[:segments].each do |segment|
        # Add route metadata to each segment for hover/click events
        segments << segment.merge(route_metadata).merge(
          # Ensure required fields for globe rendering
          color: segment[:color] || '#00f0ff',
          startLat: segment[:startLat],
          startLng: segment[:startLng],
          endLat: segment[:endLat],
          endLng: segment[:endLng]
        )
      end
    end
    
    segments.first(200) # Limit total segments for performance
  end

  def build_globe_arcs(filtered_articles, perspective, to_time)
    # 1. Flow arcs (auto-generated from article sequence)
    flow_arcs = build_article_flow_arcs(filtered_articles, perspective)

    # 2. Database arcs (seeded NarrativeArcs)
    scope = NarrativeArc.includes(article: :ai_analysis).order(:id)
    scope = scope.joins(:article).where("articles.published_at <= ?", to_time) if to_time

    db_arcs = if perspective
                scope.joins(:article).select { |arc| perspective.matches_source?(arc.article.source_name) }
                     .map { |arc| serialize_arc(arc, perspective.color) }
              else
                scope.limit(50).map { |arc| serialize_arc(arc) }
              end

    # Combine both, prioritizing DB arcs
    (db_arcs + flow_arcs).first(100)
  end

  def build_article_flow_arcs(filtered_articles, perspective)
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
      startLat:      arc.origin_lat,
      startLng:      arc.origin_lng,
      endLat:        arc.target_lat,
      endLng:        arc.target_lng,
      color:         [base_color, brighten_hex(base_color, 0.18)],
      articleId:     arc.article_id,
      headline:      arc.article&.headline,
      source:        arc.article&.source_name,
      originCountry: arc.origin_country,
      targetCountry: arc.target_country
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
