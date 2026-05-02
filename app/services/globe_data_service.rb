# Builds the full JSON payload for Globe.gl — points, arcs, routes, heatmap.
#
# Usage:
#   GlobeDataService.new(to_time:, view_mode:, search_query:, topic:).call
#   Returns: Hash ready for render json:

class GlobeDataService
  include GeoValidation
  include ArcColorHelper

  COUNTRY_COORDINATES = {
    "UKR" => [48.3794, 31.1656],
    "DEU" => [51.1657, 10.4515],
    "CHN" => [35.8617, 104.1954],
    "ISR" => [31.0461, 34.8516],
    "USA" => [37.0902, -95.7129],
    "RUS" => [61.5240, 105.3188],
    "FRA" => [46.2276, 2.2137],
    "GBR" => [55.3781, -3.4360],
    "IRN" => [32.4279, 53.6880],
    "IND" => [20.5937, 78.9629]
  }.freeze

  def initialize(to_time: nil, view_mode: "arcs", search_query: nil, topic: nil)
    @to_time      = to_time
    @view_mode    = view_mode
    @search_query = search_query
    @topic        = topic
  end

  def call
    scope = Article.includes(:country, :region, :ai_analysis)
    scope = scope.where("published_at <= ?", @to_time) if @to_time
    scope = scope.order(published_at: :desc)

    if @topic.present?
      scope = scope.where("headline ILIKE ?", "%#{@topic}%")
                   .or(scope.where("content ILIKE ?", "%#{@topic}%"))
    end

    if @search_query.present?
      scope = SearchService.new(@search_query, scope: scope, limit: 100).call
    end

    filtered_articles = scope.limit(250).to_a

    points  = build_points(filtered_articles)
    routes  = []
    arcs    = build_arcs(filtered_articles, routes)

    countries_with_articles = Country
      .joins(:articles)
      .select("countries.*, COUNT(articles.id) as article_count")
      .group("countries.id")
      .having("COUNT(articles.id) > 0")
      .order("article_count DESC")
      .limit(25)

    regions          = build_regions(countries_with_articles)
    heatmap_clusters = build_heatmap_clusters(countries_with_articles, filtered_articles)
    heatmap          = build_heatmap(filtered_articles)

    {
      points: points, arcs: arcs, routes: routes, regions: regions,
      heatmap: heatmap, heatmapClusters: heatmap_clusters,
      mode: VeritasMode.current
    }
  end

  private

  def build_points(filtered_articles)
    filtered_articles.first(200).filter_map do |a|
      next if a.latitude.blank? || a.longitude.blank?
      next if null_island?(a.latitude, a.longitude)
      next unless valid_coordinates?(a.latitude, a.longitude)

      {
        id:              a.id,
        lat:             a.latitude,
        lng:             a.longitude,
        size:            0.4,
        color:           a.ai_analysis&.sentiment_color || "#00f0ff",
        headline:        a.headline,
        source:          a.source_name,
        perspectiveSlug: SourceClassifierService.classify(a.source_name)[:slug]
      }
    end
  end

  def build_arcs(filtered_articles, routes)
    if @view_mode == "segments"
      route_payload = build_route_segments(filtered_articles)
      routes.replace(route_payload[:routes])

      if route_payload[:segments].size < 5 && @search_query.blank? && @topic.blank?
        top_payload = build_top_narrative_segments
        routes.replace((routes + top_payload[:routes]).uniq { |r| r[:id] })
        all_segments = (route_payload[:segments] + top_payload[:segments]).uniq { |s| s[:id] }
        all_segments.any? ? all_segments : build_globe_arcs(filtered_articles)
      else
        route_payload[:segments].any? ? route_payload[:segments] : build_globe_arcs(filtered_articles)
      end
    else
      build_globe_arcs(filtered_articles)
    end
  end

  def build_route_segments(filtered_articles)
    filtered_ids = filtered_articles.map(&:id)
    arc_ids = NarrativeArc.where(article_id: filtered_ids).pluck(:id)

    scope = NarrativeRoute
      .where(narrative_arc_id: arc_ids)
      .joins(narrative_arc: :article)
      .includes(narrative_arc: { article: :ai_analysis })
      .where.not(hops: nil)
      .order("narrative_routes.created_at DESC")

    scope = scope.where("articles.published_at <= ?", @to_time) if @to_time
    scope = scope.limit(100)

    scored_routes = scope.filter_map do |route|
      route_data = route.as_globe_data
      next unless route_data[:segments]&.any?

      confidences = route.hops.filter_map { |h| h["confidence_score"]&.to_f }
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
      route_data = r[:route].as_journey_data

      routes << route_data.merge(strength: strength, tier: tier)

      route_data[:segments].each do |segment|
        next if degenerate_arc?(segment)
        segments << segment.merge(strength: strength, tier: tier)
      end
    end

    { segments: segments, routes: routes }
  end

  def build_top_narrative_segments
    scope = NarrativeRoute
      .joins(narrative_arc: :article)
      .includes(narrative_arc: { article: :ai_analysis })
      .where.not(hops: nil)
      .where("narrative_routes.total_hops >= ?", 2)
      .where("narrative_routes.created_at >= ?", 7.days.ago)
      .order(manipulation_score: :desc, total_reach_countries: :desc)

    scope = scope.where("articles.published_at <= ?", @to_time) if @to_time

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

  def build_globe_arcs(filtered_articles)
    filtered_ids = filtered_articles.map(&:id)

    scope = NarrativeArc.includes(article: :ai_analysis).order(:id)
    scope = scope.where(article_id: filtered_ids) if filtered_ids.any?
    scope = scope.joins(:article).where("articles.published_at <= ?", @to_time) if @to_time

    db_arcs = scope.limit(50).map { |arc| serialize_arc(arc).merge(isNarrative: true) }
    db_arcs.reject { |arc| degenerate_arc?(arc) }.first(100)
  end

  def serialize_arc(arc)
    base_color = arc.article&.ai_analysis&.sentiment_color || arc.arc_color || DEFAULT_ARC_COLOR

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

  def build_regions(countries_with_articles)
    countries_with_articles.filter_map do |c|
      coords = COUNTRY_COORDINATES[c.iso_code]
      next unless coords

      article_count = c.attributes["article_count"].to_i
      {
        lat:          coords[0],
        lng:          coords[1],
        name:         c.name,
        threat:       [article_count, 10].min,
        radius:       article_count > 0 ? [Math.sqrt(article_count) * 0.25, 1.5].min : 0.3,
        articleCount: article_count
      }
    end
  end

  def build_heatmap_clusters(countries_with_articles, filtered_articles)
    countries_with_articles.first(15).filter_map do |c|
      coords = COUNTRY_COORDINATES[c.iso_code]
      next unless coords

      country_articles = filtered_articles.select { |a| a.country_id == c.id }
      avg_threat = if country_articles.any?
                     threats = country_articles.filter_map { |a| a.ai_analysis&.threat_numeric }
                     threats.any? ? (threats.sum.to_f / threats.size).round(1) : 0
                   else
                     0
                   end
      top_headlines = country_articles
        .sort_by { |a| -(a.ai_analysis&.threat_numeric || 0) }
        .first(3)
        .map { |a| { headline: a.headline.truncate(80), source: a.source_name } }

      {
        lat:          coords[0],
        lng:          coords[1],
        name:         c.name,
        iso:          c.iso_code,
        articleCount: c.attributes["article_count"].to_i,
        avgThreat:    avg_threat,
        topHeadlines: top_headlines
      }
    end
  end

  def build_heatmap(filtered_articles)
    filtered_articles.first(200).filter_map do |a|
      next if a.latitude.blank? || a.longitude.blank?
      next if null_island?(a.latitude, a.longitude)

      threat = a.ai_analysis&.threat_level.to_f
      trust  = a.ai_analysis&.trust_score.to_f

      weight = if a.ai_analysis.nil?
                 0.4
               else
                 ((threat / 10.0) * 0.65 + ((100.0 - trust) / 100.0) * 0.35).clamp(0.2, 1.0)
               end

      { lat: a.latitude, lng: a.longitude, weight: weight }
    end
  end
end
