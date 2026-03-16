require "ostruct"

class NarrativeSurgeDetectorService
  # Thresholds — what makes a convergence a "surge"
  SURGE_MIN_ARTICLES     = 8    # cluster must have this many articles
  SURGE_MIN_COUNTRIES    = 3    # appearing across this many countries
  SURGE_MIN_SOURCES      = 5    # from this many unique outlets
  SURGE_WINDOW_HOURS     = 6    # all within this time window
  CRITICAL_THREAT_COUNT  = 3    # or: this many CRITICAL/HIGH analyses in the window
  COOLDOWN_MINUTES       = 30   # no new alert if one fired within this window

  def initialize
    @client = OpenRouterClient.new
  end

  # Called automatically after convergence detection, or manually via stealth trigger.
  # Returns the created BreakingAlert or nil if no surge detected.
  def detect_and_alert!(force: false)
    Rails.logger.info "[SURGE] detect_and_alert! called (force=#{force})"

    if !force && cooldown_active?
      Rails.logger.info "[SURGE] Cooldown active — skipping"
      return nil
    end

    surge = find_strongest_surge
    Rails.logger.info "[SURGE] Strongest surge found: #{surge&.id} — #{surge&.label}"

    # When force=true, fall back to best available convergence or demo alert
    if surge.nil? && force
      surge = find_best_available_convergence
      Rails.logger.info "[SURGE] Force mode — using best available: #{surge&.id} — #{surge&.label}"
    end

    return nil unless surge

    alert = build_alert_from_surge(surge)
    Rails.logger.info "[SURGE] Breaking Alert created — #{alert.severity}: #{alert.headline}"
    alert
  end

  private

  def cooldown_active?
    BreakingAlert.live.where("created_at > ?", COOLDOWN_MINUTES.minutes.ago).exists?
  end

  # Returns the NarrativeConvergence that best qualifies as a surge, or nil
  def find_strongest_surge
    recent_window = SURGE_WINDOW_HOURS.hours.ago
    all_convergences = NarrativeConvergence.active.recent.to_a
    Rails.logger.info "[SURGE] Total active convergences: #{all_convergences.size}"
    all_convergences.each do |c|
      Rails.logger.info "[SURGE]   → id=#{c.id} label=#{c.label} articles=#{c.article_count} countries=#{c.countries.size} sources=#{c.source_names.size} age=#{c.calculated_at}"
    end

    candidates = all_convergences.select do |c|
      c.article_count >= SURGE_MIN_ARTICLES &&
        c.countries.size >= SURGE_MIN_COUNTRIES &&
        c.source_names.size >= SURGE_MIN_SOURCES &&
        c.calculated_at >= recent_window
    end
    Rails.logger.info "[SURGE] Qualifying candidates: #{candidates.size}"

    return nil if candidates.empty?

    # If none pass full thresholds, check for critical threat density as fallback
    if candidates.empty?
      return find_critical_threat_surge(recent_window)
    end

    # Score by: article_count weight + threat level weight + country diversity
    candidates.max_by { |c| surge_score(c) }
  end

  def find_critical_threat_surge(window)
    # Fallback: 3+ CRITICAL/HIGH analyses in the time window, cluster them
    high_threat = AiAnalysis
      .where(threat_level: %w[CRITICAL HIGH])
      .where("created_at >= ?", window)
      .includes(:article)

    return nil if high_threat.count < CRITICAL_THREAT_COUNT

    # Use the most recent high-threat article's convergence if available
    article_ids = high_threat.map(&:article_id)
    NarrativeConvergence.active.find { |c| (c.article_ids & article_ids).size >= 3 }
  end

  # Force fallback: best convergence regardless of thresholds, or a synthetic one
  def find_best_available_convergence
    all = NarrativeConvergence.active.recent.to_a
    return build_synthetic_convergence if all.empty?
    all.max_by { |c| surge_score(c) }
  end

  # Last resort: synthetic convergence from any recent articles
  def build_synthetic_convergence
    articles = Article.joins(:ai_analysis)
                      .includes(:ai_analysis, :country)
                      .order(created_at: :desc)
                      .limit(10)

    return nil if articles.empty?

    ids = articles.map(&:id)
    OpenStruct.new(
      id:                    nil,
      label:                 articles.first.ai_analysis&.geopolitical_topic || "GEOPOLITICAL ESCALATION",
      article_count:         articles.size,
      article_ids:           ids,
      countries:             articles.map { |a| a.country&.name }.compact.uniq,
      source_names:          articles.map(&:source_name).compact.uniq,
      origin_article_id:     articles.first.id,
      dominant_threat_level: "HIGH",
      avg_trust_score:       0.6,
      calculated_at:         Time.current
    )
  end

  def surge_score(convergence)
    threat_weight = case convergence.dominant_threat_level
                    when "CRITICAL" then 100
                    when "HIGH"     then 60
                    when "MODERATE" then 20
                    else 5
                    end

    convergence.article_count * 2 +
      convergence.countries.size * 10 +
      convergence.source_names.size * 5 +
      threat_weight
  end

  def build_alert_from_surge(convergence)
    articles = if convergence.respond_to?(:articles) && convergence.class != OpenStruct
                 convergence.articles.includes(:ai_analysis, :country).limit(10)
               else
                 Article.includes(:ai_analysis, :country)
                        .joins(:ai_analysis)
                        .where(id: convergence.article_ids.presence || Article.order(created_at: :desc).limit(10).ids)
                        .limit(10)
               end
    coords   = derive_coordinates(convergence, articles)
    region   = find_region_for(coords)
    briefing = generate_briefing(convergence, articles)
    severity = map_severity(convergence.dominant_threat_level)

    BreakingAlert.create!(
      headline:      format_headline(convergence),
      briefing:      briefing,
      severity:      severity,
      lat:           coords[:lat],
      lng:           coords[:lng],
      region:        region,
      source_type:   "auto",
      metadata: {
        convergence_id:    convergence.id,
        article_ids:       convergence.article_ids.first(20),
        article_count:     convergence.article_count,
        sources_involved:  convergence.source_names.size,
        countries_involved: convergence.countries.size,
        avg_trust_score:   convergence.avg_trust_score,
        dominant_threat:   convergence.dominant_threat_level
      }
    )
  end

  def derive_coordinates(convergence, articles)
    # Use origin article if available, otherwise mean of article coords
    origin = articles.find { |a| a.id == convergence.origin_article_id }
    if origin&.latitude && origin&.longitude
      return { lat: origin.latitude, lng: origin.longitude }
    end

    geolocated = articles.select { |a| a.latitude && a.longitude }
    if geolocated.any?
      lat = geolocated.sum(&:latitude) / geolocated.size
      lng = geolocated.sum(&:longitude) / geolocated.size
      return { lat: lat, lng: lng }
    end

    # Final fallback: region centroid from countries
    region = Region.joins(:countries)
                   .where(countries: { name: convergence.countries.first })
                   .first
    { lat: region&.latitude || 0.0, lng: region&.longitude || 0.0 }
  end

  def find_region_for(coords)
    # Find closest region by approximate coordinate proximity
    Region.all.min_by do |r|
      next Float::INFINITY unless r.latitude && r.longitude
      ((r.latitude - coords[:lat]).abs + (r.longitude - coords[:lng]).abs)
    end
  end

  def generate_briefing(convergence, articles)
    context = articles.first(5).map do |a|
      analysis = a.ai_analysis
      "- [#{a.source_name}] #{a.headline} (#{analysis&.threat_level || 'UNKNOWN'}, trust: #{analysis&.trust_score&.round(2) || 'N/A'})"
    end.join("\n")

    prompt = <<~PROMPT
      You are VERITAS ARBITER — a senior intelligence analyst detecting narrative operations.
      A narrative surge has been detected. Write exactly 2 sentences (max 80 words total) as an intelligence briefing.
      Be precise, clinical, and high-stakes. No hedging. Reference source count and countries if possible.

      Cluster label: #{convergence.label}
      Dominant threat level: #{convergence.dominant_threat_level}
      Articles: #{convergence.article_count} across #{convergence.countries.size} countries (#{convergence.countries.first(3).join(", ")})
      Sources: #{convergence.source_names.size} outlets (#{convergence.source_names.first(3).join(", ")})

      Sample articles:
      #{context}

      Output ONLY the 2-sentence briefing. No preamble.
    PROMPT

    response = @client.complete(
      model: :arbiter,
      prompt: prompt,
      max_tokens: 120,
      temperature: 0.3
    )

    response.strip.presence || fallback_briefing(convergence)
  rescue StandardError => e
    Rails.logger.warn "[SURGE] Briefing generation failed: #{e.message} — using fallback"
    fallback_briefing(convergence)
  end

  def fallback_briefing(convergence)
    "VERITAS has detected a coordinated narrative surge across #{convergence.source_names.size} outlets " \
    "in #{convergence.countries.size} countries. Cluster: #{convergence.label}. Dominant threat level: #{convergence.dominant_threat_level}."
  end

  def format_headline(convergence)
    label = convergence.label.upcase.truncate(60, omission: "")
    "NARRATIVE SURGE DETECTED — #{label}"
  end

  def map_severity(threat_level)
    case threat_level
    when "CRITICAL"   then :critical
    when "HIGH"       then :high
    when "MODERATE"   then :elevated
    else :moderate
    end
  end
end
