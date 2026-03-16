class PagesController < ApplicationController
  DEFAULT_ARC_COLOR = "#00f0ff".freeze

  def home
    @articles            = Article.includes(:country, :region).order(published_at: :desc)
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

    scope  = Article.includes(:country, :region, :ai_analysis)
    scope  = scope.where("published_at <= ?", to_time) if to_time
    scope  = scope.order(published_at: :desc)

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

    arcs = build_globe_arcs(filtered_articles, perspective, to_time)

    regions = Region.order(:id).map do |r|
      {
        lat:    r.latitude,
        lng:    r.longitude,
        name:   r.name,
        threat: r.threat_level.to_i
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

  def build_globe_arcs(filtered_articles, perspective, to_time)
    article_flow_arcs = build_article_flow_arcs(filtered_articles, perspective)
    return article_flow_arcs if article_flow_arcs.any?

    scope = NarrativeArc.includes(article: :ai_analysis).order(:id)
    scope = scope.joins(:article).where("articles.published_at <= ?", to_time) if to_time

    if perspective
      scope = scope.joins(:article).select { |arc| perspective.matches_source?(arc.article.source_name) }
      scope.first(50).map { |arc| serialize_arc(arc, perspective.color) }
    else
      scope.limit(50).map { |arc| serialize_arc(arc) }
    end
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
