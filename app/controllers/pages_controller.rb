class PagesController < ApplicationController
  def home
    @articles            = Article.includes(:country, :region).order(published_at: :desc).limit(50)
    @regions             = Region.order(:name)
    @perspective_filters = PerspectiveFilter.order(:name)
    @timeline_min        = Article.minimum(:published_at)&.to_i || Time.now.to_i
    @timeline_max        = Article.maximum(:published_at)&.to_i || Time.now.to_i
  end

  # GET /api/globe_data — JSON feed for Globe.gl
  def globe_data
    perspective = PerspectiveFilter.find_by(id: params[:perspective_id])
    to_time     = params[:to].present? ? Time.at(params[:to].to_i) : nil

    scope  = Article.includes(:country, :ai_analysis)
    scope  = scope.where("published_at <= ?", to_time) if to_time

    points = scope.limit(200).filter_map do |a|
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

    arcs = NarrativeArc.order(:id).limit(50).map do |arc|
      {
        startLat:      arc.origin_lat,
        startLng:      arc.origin_lng,
        endLat:        arc.target_lat,
        endLng:        arc.target_lng,
        color:         arc.arc_color || "#00f0ff",
        originCountry: arc.origin_country,
        targetCountry: arc.target_country
      }
    end

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
end
