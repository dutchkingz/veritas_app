class NarrativeRouteGeneratorService
  # Similarity threshold for considering articles as part of the same narrative.
  # cosine_distance = 1 - cosine_similarity, so max_distance = 1 - SIMILARITY_THRESHOLD.
  # 0.85 → only connect articles with ≥85% semantic similarity (was 0.65 — still too loose for text embeddings).
  SIMILARITY_THRESHOLD = 0.85
  MAX_HOPS_PER_ROUTE = 8

  def initialize(logger: Rails.logger)
    @logger = logger
    @framing_service = FramingAnalysisService.new
  end
  
  # Targeted route generation for a single article against its nearest neighbors.
  # Used by FreshIntelligenceJob — O(1) per article, not O(n²).
  def generate_routes_for_article(article)
    return 0 unless article.embedding.present?

    similar = find_similar_articles(article)
    return 0 if similar.empty?

    route = create_route_for_article(article, similar)
    route ? 1 : 0
  rescue StandardError => e
    @logger.error "[NarrativeRouteGenerator] generate_routes_for_article failed ##{article.id}: #{e.message}"
    0
  end

  # Main entry point: find articles without routes and try to connect them
  def generate_routes(limit: nil, force: false)
    @logger.info "[NarrativeRouteGenerator] Starting route generation..."
    @logger.info "[NarrativeRouteGenerator] Force mode: #{force}" if force
    
    # Get articles with embeddings
    query = Article.where.not(embedding: nil).order(published_at: :desc)
    
    # Unless force mode, only process articles without existing arcs
    query = query.where.missing(:narrative_arcs) unless force
    
    query = query.limit(limit) if limit.present?
    
    articles_to_process = query
    
    @logger.info "[NarrativeRouteGenerator] Found #{articles_to_process.count} articles to process"
    
    routes_created = 0
    
    articles_to_process.each do |article|
      begin
        similar_articles = find_similar_articles(article)
        
        if similar_articles.any?
          @logger.info "[NarrativeRouteGenerator] Article ##{article.id} has #{similar_articles.count} similar articles"
          
          # Create a route connecting this article with similar ones
          route = create_route_for_article(article, similar_articles)
          routes_created += 1 if route
        else
          @logger.info "[NarrativeRouteGenerator] Article ##{article.id} has NO similar articles (threshold #{SIMILARITY_THRESHOLD})"
        end
      rescue StandardError => e
        @logger.error "[NarrativeRouteGenerator] Failed to process Article ##{article.id}: #{e.message}"
        @logger.error e.backtrace.first(5).join("\n")
      end
    end
    
    @logger.info "[NarrativeRouteGenerator] ✅ Route generation complete: #{routes_created} routes created"
    routes_created
  end
  
  # Find articles similar to the given one using pgvector
  def find_similar_articles(article, max_results: 5)
    return [] unless article.embedding
    
    # Use pgvector's cosine distance
    # Note: cosine distance = 1 - cosine_similarity, so we want distance < (1 - threshold)
    max_distance = 1 - SIMILARITY_THRESHOLD
    
    # Use pgvector's cosine distance through the neighbor gem
    max_distance = 1 - SIMILARITY_THRESHOLD
    
    similar = Article.where.not(id: article.id)
                     .where.not(embedding: nil)
                     .where(published_at: (article.published_at - 30.days)..(article.published_at + 7.days))
                     .nearest_neighbors(:embedding, article.embedding, distance: "cosine")
                     .limit(max_results)
    
    # Debug logging
    @logger.debug "[NarrativeRouteGenerator] Article ##{article.id} '#{article.headline[0..50]}...' found #{similar.count} neighbors"
    if similar.any?
      distances = similar.map(&:neighbor_distance)
      @logger.debug "[NarrativeRouteGenerator] Distances: #{distances.map { |d| d.round(3) }}"
      @logger.debug "[NarrativeRouteGenerator] Within threshold #{SIMILARITY_THRESHOLD}? #{distances.any? { |d| d < max_distance }}"
    end
    
    # Filter by threshold
    similar.select { |a| a.neighbor_distance < max_distance }
  end
  
  # Create a narrative route from an article chain
  def create_route_for_article(origin_article, similar_articles)
    # Build a chain of hops ordered by publication time.
    # Guard against nil published_at — treat it as epoch so it sorts first and
    # the chain remains deterministic rather than crashing.
    all_articles = [origin_article] + similar_articles
    sorted_articles = all_articles.compact.sort_by { |a| a.published_at || Time.at(0) }.uniq
    
    return nil if sorted_articles.length < 2
    
    # Build hops array — only include articles with valid coordinates
    hops = sorted_articles.filter_map do |article|
      lat, lng = resolve_coordinates(article)
      next nil unless lat && lng  # Skip articles we can't place on the globe

      framing_result = detect_framing_shift(origin_article, article)
      {
        'article_id' => article.id,
        'source_name' => article.source_name,
        'source_country' => article.country&.name || country_from_domain(article.source_url),
        'lat' => lat,
        'lng' => lng,
        'published_at' => article.published_at&.iso8601,
        'framing_shift' => framing_result[:framing],
        'framing_explanation' => framing_result[:explanation],
        'framing_confidence' => framing_result[:confidence],
        'confidence_score' => calculate_confidence(origin_article, article),
        'delay_from_previous' => 0 # Will be calculated after sorting
      }
    end

    return nil if hops.length < 2
    
    # Calculate delays between hops
    hops.each_with_index do |hop, index|
      if index > 0
        prev_time = hops[index - 1]['published_at']
        curr_time = hop['published_at']
        
        if prev_time && curr_time
          delay = (DateTime.parse(curr_time) - DateTime.parse(prev_time)) * 24 * 60 * 60
          hop['delay_from_previous'] = delay.to_i
        end
      end
    end
    
    # Limit hops to MAX_HOPS_PER_ROUTE
    hops = hops.first(MAX_HOPS_PER_ROUTE)
    
    # Create or find narrative arc
    arc = NarrativeArc.find_or_create_by(
      article_id:     origin_article.id,
      origin_country: origin_article.country&.name || 'Unknown',
      origin_lat:     origin_article.latitude,
      origin_lng:     origin_article.longitude,
      target_country: hops.last['source_country'] || 'Unknown',
      target_lat:     hops.last['lat'],
      target_lng:     hops.last['lng'],
      arc_color:      determine_arc_color(hops)
    )
    
    # Create narrative route
    route = NarrativeRoute.create!(
      narrative_arc_id: arc.id,
      name: generate_route_name(sorted_articles.first, sorted_articles.last),
      description: "Automatically generated narrative route via semantic similarity",
      hops: hops,
      is_complete: hops.length >= 2,
      status: 'tracking'
    )
    
    @logger.info "[NarrativeRouteGenerator] Created route: #{route.name} (#{hops.length} hops)"
    route
  end
  
  # Determine framing shift via LLM-based comparative content analysis.
  # Returns a Hash: { framing: String, confidence: Float, explanation: String }
  def detect_framing_shift(origin, target)
    @framing_service.analyze(origin, target)
  end

  # Legacy hardcoded framing detection — kept for comparison and regression testing.
  # DO NOT use in production: assigns framing labels based on source name alone,
  # which bakes in confirmation bias (RT is always "amplified", Reuters always "neutralized").
  def detect_framing_shift_legacy(origin, target)
    return { framing: 'original', confidence: 1.0, explanation: 'Same article.' } if origin.id == target.id

    source_name = target.source_name.to_s.downcase

    framing = if source_name.include?('rt') || source_name.include?('sputnik') || source_name.include?('xinhua')
      'amplified'
    elsif source_name.include?('breitbart') || source_name.include?('daily wire')
      'amplified'
    elsif source_name.include?('cnn') || source_name.include?('msnbc')
      'amplified'
    elsif contains_distortion_indicators?(origin.headline, target.headline)
      'distorted'
    else
      'neutralized'
    end

    { framing: framing, confidence: 0.5, explanation: "(legacy: classified by source name)" }
  end
  
  # Very basic confidence calculation based on embedding similarity
  def calculate_confidence(origin, target)
    return 0.5 unless origin.embedding && target.embedding
    
    # Cosine similarity
    dot_product = origin.embedding.zip(target.embedding).map { |a, b| a * b }.sum
    magnitude_origin = Math.sqrt(origin.embedding.map { |x| x ** 2 }.sum)
    magnitude_target = Math.sqrt(target.embedding.map { |x| x ** 2 }.sum)
    
    return 0.5 if magnitude_origin == 0 || magnitude_target == 0
    
    similarity = dot_product / (magnitude_origin * magnitude_target)
    # Normalize to 0.5-0.95 range
    [0.5, [0.95, (similarity + 1) / 2].min].max.round(2)
  end
  
  # Check if headline changed significantly (rough distortion detection)
  def contains_distortion_indicators?(original_headline, target_headline)
    orig_words = original_headline.to_s.downcase.split(/\W+/)
    target_words = target_headline.to_s.downcase.split(/\W+/)
    
    # Check if significant words were added/removed
    orig_significant = orig_words.select { |w| w.length > 4 }
    target_significant = target_words.select { |w| w.length > 4 }
    
    jaccard = (orig_significant & target_significant).length.to_f / 
              (orig_significant | target_significant).length
    
    jaccard < 0.4 # Less than 40% word overlap suggests distortion
  end
  
  def determine_arc_color(hops)
    # Determine arc color based on dominant framing shift
    shifts = hops.map { |h| h['framing_shift'] }
    
    if shifts.count('distorted') > shifts.count('original')
      '#ef4444' # Red for distorted narratives
    elsif shifts.count('amplified') > 2
      '#f59e0b' # Yellow for amplified
    else
      '#22c55e' # Green for original/neutralized
    end
  end
  
  def generate_route_name(first, last)
    "Narrative Route: #{first.source_name} → #{last.source_name}"
  end

  # Infer country name from a URL's top-level domain when no other
  # country data is available. Covers the most common ccTLDs seen in
  # OSINT news sources. Returns nil for generic TLDs (.com, .org, .net).
  DOMAIN_COUNTRY_MAP = {
    "ru" => "Russia", "cn" => "China", "ir" => "Iran", "il" => "Israel",
    "ua" => "Ukraine", "de" => "Germany", "fr" => "France", "uk" => "United Kingdom",
    "jp" => "Japan", "kr" => "South Korea", "in" => "India", "br" => "Brazil",
    "tr" => "Turkey", "sa" => "Saudi Arabia", "pk" => "Pakistan", "eg" => "Egypt",
    "ng" => "Nigeria", "za" => "South Africa", "au" => "Australia", "ca" => "Canada",
    "mx" => "Mexico", "ar" => "Argentina", "pl" => "Poland", "es" => "Spain",
    "it" => "Italy", "nl" => "Netherlands", "se" => "Sweden", "no" => "Norway",
    "fi" => "Finland", "dk" => "Denmark", "at" => "Austria", "ch" => "Switzerland",
    "be" => "Belgium", "ie" => "Ireland", "pt" => "Portugal", "cz" => "Czechia",
    "ro" => "Romania", "hu" => "Hungary", "gr" => "Greece", "tw" => "Taiwan",
    "th" => "Thailand", "ph" => "Philippines", "my" => "Malaysia", "sg" => "Singapore",
    "id" => "Indonesia", "vn" => "Vietnam", "qa" => "Qatar", "ae" => "UAE",
    "ke" => "Kenya", "gh" => "Ghana", "et" => "Ethiopia", "tz" => "Tanzania",
    "co" => "Colombia", "cl" => "Chile", "pe" => "Peru", "ve" => "Venezuela"
  }.freeze

  def country_from_domain(url)
    return nil if url.blank?
    host = URI.parse(url.strip).host.to_s.downcase
    # Extract ccTLD: last segment unless it's a known generic TLD
    tld = host.split(".").last
    # Handle two-part ccTLDs like .co.uk, .com.au
    if %w[uk au].include?(tld)
      parts = host.split(".")
      tld = parts[-1] if parts.length >= 3 && parts[-2].length <= 3
    end
    DOMAIN_COUNTRY_MAP[tld]
  rescue URI::InvalidURIError
    nil
  end

  # Resolve valid coordinates for an article. Returns [lat, lng] or nil.
  # Priority: article's own coords → country centroid → source HQ via GeolocatorService
  def resolve_coordinates(article)
    lat = article.latitude
    lng = article.longitude

    # Already has valid, non-ocean coordinates
    if lat && lng && valid_land_coordinates?(lat, lng)
      return [lat, lng]
    end

    # Try the article's country centroid
    if article.country&.latitude && article.country&.longitude
      return [article.country.latitude, article.country.longitude]
    end

    # Try GeolocatorService source fallback (maps source name → country HQ)
    geo = GeolocatorService.new(
      title: article.headline,
      description: "",
      source_name: article.source_name
    ).call
    if geo[:latitude] && geo[:longitude] && geo[:geo_method] != "unresolved"
      return [geo[:latitude], geo[:longitude]]
    end

    nil
  end

  # Basic land validation — reject coordinates that are clearly in open ocean.
  # Not a perfect land mask, but catches the worst offenders.
  def valid_land_coordinates?(lat, lng)
    # Reject null island area
    return false if lat.abs < 1.0 && lng.abs < 1.0

    # South Atlantic Ocean (roughly -5 to -60 lat, -50 to 20 lng — no major landmasses)
    if lat < -5 && lat > -60 && lng > -50 && lng < 20
      return false
    end

    # Central Pacific (far from any land)
    if lat.abs < 30 && lng < -100 && lng > -170
      return false
    end

    # North Atlantic (mid-ocean, no land between 20-60N, -20 to -50W roughly)
    if lat > 20 && lat < 60 && lng > -50 && lng < -20
      # Allow Greenland/Iceland area (lat > 55)
      return true if lat > 55
      return false
    end

    true
  end
end
