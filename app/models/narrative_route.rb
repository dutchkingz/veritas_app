require "set"

class NarrativeRoute < ApplicationRecord
  DEFAULT_MANIPULATION_SCORE = 10
  HOP_MATCH_WINDOW = 4.hours

  FRAMING_SHIFT_COLORS = {
    "original" => "#22c55e",
    "amplified" => "#f59e0b",
    "distorted" => "#ef4444",
    "neutralized" => "#3b82f6"
  }.freeze

  FRAMING_SHIFT_INCREMENTS = {
    "original" => 4,
    "neutralized" => 8,
    "amplified" => 16,
    "distorted" => 24
  }.freeze

  FRAMING_SCORE_LABELS = [
    [20, "ORIGINAL"],
    [40, "AMPLIFIED"],
    [60, "CONCERNING"],
    [80, "HOSTILE"],
    [100, "CRITICAL THREAT"]
  ].freeze

  PERSPECTIVE_COLORS = {
    "western_mainstream" => "#38bdf8",
    "us_liberal" => "#60a5fa",
    "us_conservative" => "#f87171",
    "china_state" => "#f97316",
    "russia_state" => "#dc2626",
    "global_south" => "#eab308",
    "unclassified" => "#64748b"
  }.freeze

  PERSPECTIVE_FLAGS = {
    "western_mainstream" => "WORLD",
    "us_liberal" => "US-L",
    "us_conservative" => "US-R",
    "china_state" => "CN",
    "russia_state" => "RU",
    "global_south" => "GS",
    "unclassified" => "OT"
  }.freeze

  belongs_to :narrative_arc
  belongs_to :article, optional: true

  validates :hops, presence: true
  validates :total_hops, numericality: { greater_than_or_equal_to: 0 }
  validates :manipulation_score, numericality: { in: 0.0..1.0 }
  validates :amplification_score, numericality: { in: 0.0..1.0 }

  before_save :calculate_derived_fields
  after_save :update_arc_metadata

  def as_globe_data
    return simple_globe_data if hops.empty?

    as_journey_data
  end

  def as_journey_data
    return simple_globe_data if hops.empty?

    serialized_hops = build_serialized_hops
    route_name = name.presence || default_route_name(serialized_hops)
    segments = build_segments(serialized_hops, route_name)
    enrich_segments_with_gdelt!(segments)

    {
      id: id,
      routeId: id,
      name: route_name,
      routeName: route_name,
      description: description,
      arcId: narrative_arc_id,
      articleId: narrative_arc&.article_id || article_id || serialized_hops.first[:articleId],
      totalHops: serialized_hops.size,
      totalSegments: segments.size,
      propagationSpeed: propagation_speed,
      routeManipulationScore: manipulation_score,
      amplificationScore: amplification_score,
      totalDurationSeconds: duration_seconds(serialized_hops),
      totalReachCountries: serialized_hops.map { |hop| hop[:country] }.compact.uniq.size,
      timeline: timeline,
      isComplete: is_complete,
      originCountry: serialized_hops.first[:country],
      targetCountry: serialized_hops.last[:country],
      startLat: serialized_hops.first[:lat],
      startLng: serialized_hops.first[:lng],
      endLat: serialized_hops.last[:lat],
      endLng: serialized_hops.last[:lng],
      color: score_color(serialized_hops.last[:manipulationScore]),
      origin: serialized_hops.first,
      destination: serialized_hops.last,
      hops: serialized_hops,
      segments: segments
    }
  end

  def simple_globe_data
    {
      startLat: origin_lat,
      startLng: origin_lng,
      endLat: target_lat,
      endLng: target_lng,
      color: arc_color || "#00f0ff",
      originCountry: origin_country,
      targetCountry: target_country,
      articleId: article_id
    }
  end

  private

  # Enrich segments in-place with linked GdeltEvent data.
  # Batch-loads events for all article_ids to avoid N+1 queries.
  # Each segment gets optional gdelt* fields — nil when no event is linked.
  def enrich_segments_with_gdelt!(segments)
    article_ids = segments.flat_map { |s| [ s[:articleId], s[:sourceArticleId] ] }.compact.uniq
    return if article_ids.empty?

    # Pick the most destabilizing event per article (lowest Goldstein scale)
    events_by_article = GdeltEvent
      .where(article_id: article_ids)
      .order(goldstein_scale: :asc)
      .group_by(&:article_id)

    segments.each do |seg|
      event = events_by_article[seg[:sourceArticleId]]&.first ||
              events_by_article[seg[:articleId]]&.first
      next unless event

      seg[:gdeltActorSummary]      = event.actor_summary
      seg[:gdeltEventDescription]  = event.event_description
      seg[:gdeltGoldsteinScale]    = event.goldstein_scale
      seg[:gdeltQuadClassLabel]    = event.quad_class_label
    end
  end

  def build_serialized_hops
    matched_articles = resolve_hop_articles
    current_score = DEFAULT_MANIPULATION_SCORE

    hops.each_with_index.map do |raw_hop, index|
      article = matched_articles[index]
      article ||= origin_article if index.zero?

      shift = normalized_shift(raw_hop["framing_shift"])
      current_score = next_hop_score(current_score, shift, index)
      published_at = parse_time(raw_hop["published_at"]) || article&.published_at
      source_name = raw_hop["source_name"].presence || article&.source_name || origin_article&.source_name || "Unknown Source"
      classifier = SourceClassifierService.classify(source_name.to_s)
      raw_sentiment = article&.ai_analysis&.sentiment_label.to_s
      confidence = normalize_confidence(raw_hop["confidence_score"])
      country_name = raw_hop["source_country"].presence || article&.country&.name || fallback_country_name(index)

      {
        index: index,
        articleId: raw_hop["article_id"].presence || article&.id,
        sourceName: source_name,
        headline: raw_hop["headline"].presence || article&.headline || origin_article&.headline,
        country: country_name,
        countryCode: article&.country&.iso_code,
        city: raw_hop["source_city"].presence || extract_city(article) || country_name || "Unknown",
        lat: raw_hop["lat"] || article&.latitude || fallback_lat(index),
        lng: raw_hop["lng"] || article&.longitude || fallback_lng(index),
        publishedAt: published_at&.iso8601,
        timestampMs: published_at&.to_i.to_i * 1000,
        delaySeconds: raw_hop["delay_from_previous"].to_i,
        framingShift: shift,
        framingExplanation: raw_hop["framing_explanation"],
        framingLabel: framing_label_for_score(current_score),
        framingColor: segment_color(shift),
        journeyColor: score_color(current_score),
        manipulationScore: current_score,
        confidenceScore: confidence,
        semanticSimilarity: (confidence * 100).round,
        sentimentLabel: normalized_sentiment_label(raw_sentiment),
        rawSentimentLabel: raw_sentiment.presence || "Unknown",
        sentimentColor: article&.ai_analysis&.sentiment_color || sentiment_color_for_label(raw_sentiment),
        trustScore: article&.ai_analysis&.trust_score&.round(1),
        perspectiveSlug: classifier[:slug],
        perspectiveLabel: SourceClassifierService.display_name(classifier[:slug]),
        perspectiveColor: perspective_color(classifier[:slug]),
        perspectiveFlag: PERSPECTIVE_FLAGS[classifier[:slug]] || "OT",
        perspectiveTag: perspective_tag(classifier[:slug])
      }
    end
  end

  def build_segments(serialized_hops, route_name)
    total_segments = serialized_hops.size - 1
    thickness = [(manipulation_score || 0.5) * 0.8, 0.2].max.round(2)
    origin_score = serialized_hops.first[:manipulationScore]

    serialized_hops.each_cons(2).with_index.filter_map do |(source_hop, target_hop), index|
      # Skip degenerate segments (same point or null island)
      next if degenerate_segment?(source_hop, target_hop)

      {
        id: "#{id}-#{index}",
        routeId: id,
        routeName: route_name,
        arcId: narrative_arc_id,
        articleId: narrative_arc&.article_id || article_id || source_hop[:articleId],
        sourceArticleId: source_hop[:articleId],
        targetArticleId: target_hop[:articleId],
        startLat: source_hop[:lat],
        startLng: source_hop[:lng],
        endLat: target_hop[:lat],
        endLng: target_hop[:lng],
        color: segment_color(target_hop[:framingShift]),
        journeyColor: target_hop[:journeyColor],
        thickness: thickness,
        sourceName: source_hop[:sourceName],
        targetSourceName: target_hop[:sourceName],
        sourceCountry: source_hop[:country],
        targetCountry: target_hop[:country],
        sourceCity: source_hop[:city],
        targetCity: target_hop[:city],
        sourceHeadline: source_hop[:headline],
        targetHeadline: target_hop[:headline],
        sourcePublishedAt: source_hop[:publishedAt],
        targetPublishedAt: target_hop[:publishedAt],
        publishedAt: target_hop[:publishedAt],
        delaySeconds: target_hop[:delaySeconds],
        confidenceScore: target_hop[:confidenceScore],
        semanticSimilarity: target_hop[:semanticSimilarity],
        segmentIndex: index,
        totalSegments: total_segments,
        framingShift: target_hop[:framingShift],
        framingExplanation: target_hop[:framingExplanation],
        framingLabel: target_hop[:framingLabel],
        sourceFramingLabel: source_hop[:framingLabel],
        targetFramingLabel: target_hop[:framingLabel],
        manipulationScore: target_hop[:manipulationScore],
        driftDelta: (target_hop[:manipulationScore] - origin_score).abs,
        sourceTrustScore: source_hop[:trustScore],
        targetTrustScore: target_hop[:trustScore],
        sourceSentimentLabel: source_hop[:sentimentLabel],
        targetSentimentLabel: target_hop[:sentimentLabel],
        sentimentShift: build_sentiment_shift(source_hop[:rawSentimentLabel], target_hop[:rawSentimentLabel]),
        sentimentDelta: compute_sentiment_delta(source_hop[:rawSentimentLabel], target_hop[:rawSentimentLabel]),
        driftIntensity: compute_drift_intensity(
          target_hop[:framingShift],
          source_hop[:rawSentimentLabel],
          target_hop[:rawSentimentLabel],
          target_hop[:confidenceScore]
        ),
        sourcePerspectiveSlug: source_hop[:perspectiveSlug],
        targetPerspectiveSlug: target_hop[:perspectiveSlug],
        sourcePerspectiveLabel: source_hop[:perspectiveLabel],
        targetPerspectiveLabel: target_hop[:perspectiveLabel],
        sourcePerspectiveColor: source_hop[:perspectiveColor],
        targetPerspectiveColor: target_hop[:perspectiveColor],
        perspectiveSlug: target_hop[:perspectiveSlug],
        perspectiveLabel: target_hop[:perspectiveLabel],
        perspectiveColor: target_hop[:perspectiveColor]
      }
    end
  end

  def resolve_hop_articles
    explicit_articles = Article
      .includes(:country, :ai_analysis)
      .where(id: hops.filter_map { |hop| hop["article_id"] }.uniq)
      .index_by(&:id)

    source_names = hops.filter_map { |hop| hop["source_name"].presence }.uniq
    published_times = hops.filter_map { |hop| parse_time(hop["published_at"]) }

    candidates = if source_names.any?
      scope = Article.includes(:country, :ai_analysis).where(source_name: source_names)
      if published_times.any?
        scope = scope.where(published_at: (published_times.min - HOP_MATCH_WINDOW)..(published_times.max + HOP_MATCH_WINDOW))
      end
      scope.to_a
    else
      []
    end

    grouped_candidates = candidates.group_by(&:source_name)
    used_article_ids = Set.new

    hops.each_with_index.map do |raw_hop, index|
      explicit_id = raw_hop["article_id"]&.to_i
      explicit = explicit_articles[explicit_id]
      if explicit
        used_article_ids << explicit.id
        next explicit
      end

      if index.zero? && origin_article
        used_article_ids << origin_article.id
        next origin_article
      end

      source_name = raw_hop["source_name"].presence
      published_at = parse_time(raw_hop["published_at"])
      pool = Array(grouped_candidates[source_name]).reject { |article| used_article_ids.include?(article.id) }

      candidate = if published_at
        pool.min_by { |article| time_distance(article.published_at, published_at) }
      else
        pool.first
      end

      if candidate && published_at && time_distance(candidate.published_at, published_at) <= HOP_MATCH_WINDOW
        used_article_ids << candidate.id
        candidate
      else
        candidate
      end
    end
  end

  def calculate_derived_fields
    return if hops.blank?

    self.total_hops = hops.length
    self.first_hop_at = parse_time(hops.first["published_at"])
    self.last_hop_at = parse_time(hops.last["published_at"])

    if first_hop_at && last_hop_at
      self.total_duration_seconds = (last_hop_at.to_time - first_hop_at.to_time).to_i
    end

    if hops.length >= 2
      first = hops.first
      last = hops.last
      distance_km = haversine_distance(first["lat"], first["lng"], last["lat"], last["lng"])
      hours = total_duration_seconds.to_f / 3600
      self.propagation_speed = hours.positive? ? distance_km / hours : 0
    end

    framing_shifts = hops.map { |hop| hop["framing_shift"] }.uniq
    self.manipulation_score = (framing_shifts.length - 1) / [hops.length - 1, 1].max.to_f

    countries = hops.map { |hop| hop["source_country"] }.compact.uniq
    self.total_reach_countries = countries.length
    self.amplification_score = total_reach_countries.to_f / [hops.length, 1].max

    self.timeline = hops.map do |hop|
      {
        timestamp: hop["published_at"],
        lat: hop["lat"],
        lng: hop["lng"],
        source_name: hop["source_name"],
        country: hop["source_country"],
        framing_shift: hop["framing_shift"]
      }
    end

    self.is_complete = hops.all? { |hop| normalize_confidence(hop["confidence_score"]) > 0.7 }
  end

  def update_arc_metadata
    update_hash = {}

    if hops.first
      update_hash[:origin_country] = hops.first["source_country"]
      update_hash[:origin_lat] = hops.first["lat"]
      update_hash[:origin_lng] = hops.first["lng"]
    end

    if hops.last
      update_hash[:target_country] = hops.last["source_country"]
      update_hash[:target_lat] = hops.last["lat"]
      update_hash[:target_lng] = hops.last["lng"]
    end

    narrative_arc.update(update_hash) if update_hash.any?
  end

  def origin_article
    @origin_article ||= narrative_arc&.article
  end

  def fallback_country_name(index)
    return origin_country if index.zero?
    target_country.presence || origin_country
  end

  def fallback_lat(index)
    index.zero? ? origin_lat : target_lat
  end

  def fallback_lng(index)
    index.zero? ? origin_lng : target_lng
  end

  def next_hop_score(current_score, shift, index)
    return DEFAULT_MANIPULATION_SCORE if index.zero?

    [(current_score + FRAMING_SHIFT_INCREMENTS.fetch(shift, 8)), 100].min
  end

  def normalize_confidence(value)
    value.to_f.clamp(0.0, 1.0).round(2)
  end

  def framing_label_for_score(score)
    FRAMING_SCORE_LABELS.find { |threshold, _label| score <= threshold }&.last || "CRITICAL THREAT"
  end

  def normalized_shift(value)
    FRAMING_SHIFT_COLORS.key?(value.to_s) ? value.to_s : "neutralized"
  end

  def normalized_sentiment_label(value)
    label = value.to_s.downcase
    return "POSITIVE" if label.include?("positive") || label.include?("bullish")
    return "NEGATIVE" if label.include?("negative") || label.include?("bearish") || label.include?("hostile")

    "NEUTRAL"
  end

  def sentiment_color_for_label(value)
    case normalized_sentiment_label(value)
    when "POSITIVE"
      "#22c55e"
    when "NEGATIVE"
      "#ef4444"
    else
      "#38bdf8"
    end
  end

  def perspective_color(slug)
    PERSPECTIVE_COLORS[slug] || PERSPECTIVE_COLORS["unclassified"]
  end

  def perspective_tag(slug)
    "#{PERSPECTIVE_FLAGS[slug] || 'OT'} #{SourceClassifierService.display_name(slug).upcase}"
  end

  def duration_seconds(serialized_hops)
    return total_duration_seconds if total_duration_seconds.to_i.positive?

    first_time = parse_time(serialized_hops.first[:publishedAt])
    last_time = parse_time(serialized_hops.last[:publishedAt])
    return 0 unless first_time && last_time

    (last_time.to_time - first_time.to_time).to_i
  end

  def default_route_name(serialized_hops)
    "Narrative Route: #{serialized_hops.first[:sourceName]} -> #{serialized_hops.last[:sourceName]}"
  end

  def parse_time(value)
    return if value.blank?

    value.is_a?(Time) || value.is_a?(ActiveSupport::TimeWithZone) ? value : Time.zone.parse(value.to_s)
  rescue ArgumentError
    nil
  end

  def time_distance(time_a, time_b)
    return Float::INFINITY unless time_a && time_b

    (time_a.to_time - time_b.to_time).abs
  end

  def extract_city(article)
    return unless article&.raw_data.is_a?(Hash)

    %w[city city_name source_city location_name].each do |key|
      value = article.raw_data[key]
      return value if value.present?
    end

    location = article.raw_data["location"]
    if location.is_a?(Hash)
      %w[city name label].each do |key|
        value = location[key]
        return value if value.present?
      end
    end

    nil
  end

  def score_color(score)
    return interpolate_color("#22c55e", "#f59e0b", score / 40.0) if score <= 40

    interpolate_color("#f59e0b", "#ef4444", (score - 40) / 60.0)
  end

  def interpolate_color(start_hex, end_hex, weight)
    start_rgb = start_hex.delete("#").scan(/../).map { |pair| pair.to_i(16) }
    end_rgb = end_hex.delete("#").scan(/../).map { |pair| pair.to_i(16) }
    blend = weight.clamp(0.0, 1.0)

    rgb = start_rgb.zip(end_rgb).map do |from, to|
      (from + ((to - from) * blend)).round
    end

    format("#%02x%02x%02x", *rgb)
  end

  def haversine_distance(lat1, lng1, lat2, lng2)
    rad_per_deg = Math::PI / 180
    earth_radius_km = 6371

    lat1_rad = lat1.to_f * rad_per_deg
    lat2_rad = lat2.to_f * rad_per_deg

    dlat = (lat2.to_f - lat1.to_f) * rad_per_deg
    dlng = (lng2.to_f - lng1.to_f) * rad_per_deg

    a = Math.sin(dlat / 2)**2 +
      Math.cos(lat1_rad) * Math.cos(lat2_rad) * Math.sin(dlng / 2)**2
    c = 2 * Math.asin(Math.sqrt(a))

    earth_radius_km * c
  end

  def segment_color(framing_shift)
    FRAMING_SHIFT_COLORS[framing_shift.to_s] || "#6b7280"
  end

  def degenerate_segment?(source_hop, target_hop)
    s_lat = source_hop[:lat]
    s_lng = source_hop[:lng]
    e_lat = target_hop[:lat]
    e_lng = target_hop[:lng]

    # Any nil coordinate = degenerate
    return true if [s_lat, s_lng, e_lat, e_lng].any?(&:nil?)
    # Null island (within 1° of 0,0)
    return true if (s_lat.to_f.abs < 1.0 && s_lng.to_f.abs < 1.0) || (e_lat.to_f.abs < 1.0 && e_lng.to_f.abs < 1.0)
    # Too close (within 2°) = spike/needle
    return true if (s_lat.to_f - e_lat.to_f).abs < 2.0 && (s_lng.to_f - e_lng.to_f).abs < 2.0

    false
  end

  # --- Drift metrics helpers ---

  SENTIMENT_VALUES = {
    "very positive" => 2.0, "positive" => 1.0, "bullish" => 1.0,
    "neutral" => 0.0, "mixed" => 0.0,
    "negative" => -1.0, "bearish" => -1.0, "hostile" => -1.5,
    "very negative" => -2.0
  }.freeze

  def sentiment_numeric(raw_label)
    label = raw_label.to_s.downcase.strip
    return 0.0 if label.blank? || label == "unknown"

    SENTIMENT_VALUES.each do |key, value|
      return value if label.include?(key)
    end
    0.0
  end

  def build_sentiment_shift(source_label, target_label)
    src = normalized_sentiment_label(source_label.to_s)
    tgt = normalized_sentiment_label(target_label.to_s)
    return "Unknown" if src == "NEUTRAL" && tgt == "NEUTRAL" && source_label.blank? && target_label.blank?

    "#{src.capitalize} → #{tgt.capitalize}"
  end

  def compute_sentiment_delta(source_label, target_label)
    (sentiment_numeric(target_label) - sentiment_numeric(source_label)).round(2)
  end

  def compute_drift_intensity(framing_shift, source_sentiment, target_sentiment, confidence_score)
    framing_weight = case framing_shift.to_s
                     when "original"    then 0.0
                     when "neutralized" then 0.3
                     when "amplified"   then 0.5
                     when "distorted"   then 1.0
                     else 0.0
                     end

    sentiment_weight = (compute_sentiment_delta(source_sentiment, target_sentiment).abs / 2.0).clamp(0.0, 1.0)

    semantic_distance = 1.0 - (confidence_score || 1.0).to_f.clamp(0.0, 1.0)

    ((framing_weight * 0.5) + (sentiment_weight * 0.3) + (semantic_distance * 0.2)).clamp(0.0, 1.0).round(3)
  end
end
