class NarrativeRouteGeneratorService
  # Similarity threshold for considering articles as part of the same narrative.
  # cosine_distance = 1 - cosine_similarity, so max_distance = 1 - SIMILARITY_THRESHOLD.
  # 0.65 → only connect articles with ≥65% semantic similarity (was 0.45 — far too loose).
  SIMILARITY_THRESHOLD = 0.65
  MAX_HOPS_PER_ROUTE = 8
  
  def initialize(logger: Rails.logger)
    @logger = logger
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
    
    # Direct SQL query to get distances
    sql = <<~SQL
      SELECT id, headline, source_name, published_at, latitude, longitude,
             embedding <=> '#{article.embedding.to_json}'::vector AS distance
      FROM articles 
      WHERE id != #{article.id}
        AND embedding IS NOT NULL
        AND published_at >= '#{article.published_at - 30.days}'
        AND published_at <= '#{article.published_at + 7.days}'
      ORDER BY embedding <=> '#{article.embedding.to_json}'::vector
      LIMIT #{max_results}
    SQL
    
    results = ActiveRecord::Base.connection.execute(sql)
    
    # Convert to Article objects with distance
    similar = []
    results.each do |row|
      article_obj = Article.find(row['id'])
      article_obj.instance_variable_set(:@neighbor_distance, row['distance'].to_f)
      similar << article_obj
    end
    
    # Debug logging
    @logger.debug "[NarrativeRouteGenerator] Article ##{article.id} '#{article.headline[0..50]}...' found #{similar.count} neighbors"
    if similar.any?
      distances = similar.map { |a| a.instance_variable_get(:@neighbor_distance) }
      @logger.debug "[NarrativeRouteGenerator] Distances: #{distances.map { |d| d.round(3) }}"
      @logger.debug "[NarrativeRouteGenerator] Within threshold #{SIMILARITY_THRESHOLD}? #{distances.any? { |d| d < max_distance }}"
    end
    
    # Filter by threshold
    similar.select { |a| a.instance_variable_get(:@neighbor_distance) < max_distance }
  end
  
  # Create a narrative route from an article chain
  def create_route_for_article(origin_article, similar_articles)
    # Build a chain of hops ordered by publication time.
    # Guard against nil published_at — treat it as epoch so it sorts first and
    # the chain remains deterministic rather than crashing.
    all_articles = [origin_article] + similar_articles
    sorted_articles = all_articles.compact.sort_by { |a| a.published_at || Time.at(0) }.uniq
    
    return nil if sorted_articles.length < 2
    
    # Build hops array
    hops = sorted_articles.map do |article|
      {
        'source_name' => article.source_name,
        'source_country' => article.country&.name,
        'lat' => article.latitude,
        'lng' => article.longitude,
        'published_at' => article.published_at&.iso8601,
        'framing_shift' => detect_framing_shift(origin_article, article),
        'confidence_score' => calculate_confidence(origin_article, article),
        'delay_from_previous' => 0 # Will be calculated after sorting
      }
    end
    
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
  
  # Determine framing shift based on article similarity and source type
  def detect_framing_shift(origin, target)
    return 'original' if origin.id == target.id
    
    # Simple heuristics based on source patterns
    source_name = target.source_name.to_s.downcase
    
    if source_name.include?('rt') || source_name.include?('sputnik') || source_name.include?('xinhua')
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
end
