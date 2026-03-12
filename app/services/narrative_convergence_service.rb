class NarrativeConvergenceService
  # Cosine distance threshold — articles within this distance share the same narrative
  # cosine_distance = 1 - cosine_similarity, so 0.15 ≈ 85% similar
  COSINE_THRESHOLD   = 0.15
  MIN_CLUSTER_SIZE   = 4   # minimum articles to flag as a convergence
  MIN_UNIQUE_SOURCES = 3   # minimum distinct outlets
  LOOKBACK_DAYS      = 7
  MAX_ARTICLES       = 200 # safety cap on DB load per run

  THREAT_PRIORITY = %w[CRITICAL HIGH MODERATE LOW NEGLIGIBLE].freeze

  def initialize
    @client = OpenRouterClient.new
  end

  def detect
    Rails.logger.info "[CONVERGENCE] Detection run started at #{Time.current}"

    articles = load_candidate_articles
    Rails.logger.info "[CONVERGENCE] #{articles.size} candidate articles loaded"
    return [] if articles.size < MIN_CLUSTER_SIZE

    clusters = build_clusters(articles)
    Rails.logger.info "[CONVERGENCE] #{clusters.size} raw clusters found"

    qualifying = clusters.select do |cluster|
      cluster.size >= MIN_CLUSTER_SIZE &&
        cluster.map(&:source_name).uniq.size >= MIN_UNIQUE_SOURCES
    end
    Rails.logger.info "[CONVERGENCE] #{qualifying.size} qualifying convergences"

    # Purge stale detections before writing fresh ones
    NarrativeConvergence.where(calculated_at: ..48.hours.ago).delete_all

    qualifying.filter_map { |cluster| persist_convergence(cluster) }
  end

  private

  def load_candidate_articles
    Article
      .joins(:ai_analysis)
      .where(published_at: LOOKBACK_DAYS.days.ago..Time.current)
      .where.not(embedding: nil)
      .where(ai_analyses: { analysis_status: 'complete' })
      .where.not(ai_analyses: { summary: [nil, ''] })
      .includes(:ai_analysis, :country)
      .order(published_at: :desc)
      .limit(MAX_ARTICLES)
  end

  # Union-Find clustering via pgvector nearest-neighbor queries
  def build_clusters(articles)
    article_ids = articles.map(&:id)
    parent = article_ids.index_with { |id| id }

    find_root = ->(id) {
      while parent[id] != id
        parent[id] = parent[parent[id]] # path halving
        id = parent[id]
      end
      id
    }

    union = ->(x, y) {
      px = find_root.(x)
      py = find_root.(y)
      parent[px] = py unless px == py
    }

    articles.each do |article|
      article.nearest_neighbors(:embedding, distance: "cosine")
             .where(id: article_ids)
             .where.not(id: article.id)
             .limit(25)
             .each do |neighbor|
        union.(article.id, neighbor.id) if neighbor.neighbor_distance < COSINE_THRESHOLD
      end
    end

    # Group articles by cluster root
    article_map = articles.index_by(&:id)
    clusters = Hash.new { |h, k| h[k] = [] }
    articles.each { |a| clusters[find_root.(a.id)] << a }
    clusters.values
  end

  def persist_convergence(cluster)
    label = generate_label(cluster)
    return nil unless label.present?

    origin   = cluster.min_by(&:published_at)
    countries     = cluster.filter_map { |a| a.country&.iso_code }.uniq
    source_names  = cluster.map(&:source_name).uniq
    trust_scores  = cluster.map { |a| a.ai_analysis.trust_score.to_f }.compact
    threat_levels = cluster.map { |a| a.ai_analysis.threat_level }.compact

    dominant_threat = THREAT_PRIORITY.find { |t| threat_levels.include?(t) } || 'UNKNOWN'
    avg_trust       = trust_scores.any? ? (trust_scores.sum / trust_scores.size).round(1) : 0
    diversity_pct   = (source_names.size.to_f / cluster.size * 100).round(1)

    metadata = {
      label:                label,
      article_ids:          cluster.map(&:id),
      countries:            countries,
      source_names:         source_names,
      origin_article_id:    origin.id,
      origin_country:       origin.country&.iso_code || origin.country&.name || 'UNKNOWN',
      dominant_threat_level: dominant_threat,
      avg_trust_score:      avg_trust
    }

    nc = NarrativeConvergence.create!(
      topic_keyword:          metadata.to_json,
      article_count:          cluster.size,
      convergence_percentage: diversity_pct,
      calculated_at:          Time.current
    )

    Rails.logger.info "[CONVERGENCE] ✓ #{label} — #{cluster.size} articles, #{countries.size} countries, threat: #{dominant_threat}"
    nc
  rescue StandardError => e
    Rails.logger.error "[CONVERGENCE] Failed to persist cluster: #{e.message}"
    nil
  end

  def generate_label(cluster)
    headlines = cluster.first(6).map { |a| "- #{a.headline}" }.join("\n")
    system_prompt = <<~SYS
      You are an intelligence analyst. Given these news headlines from a detected narrative cluster,
      produce a single 3-7 word topic label in ALL CAPS that captures the core geopolitical narrative.
      Output ONLY the label — no punctuation, no explanation, nothing else.
    SYS
    label = @client.chat(:arbiter, system_prompt, headlines, expect_json: false)&.strip
    label.present? ? label.upcase.gsub(/[^A-Z0-9 ]/, '').strip : nil
  rescue StandardError => e
    Rails.logger.error "[CONVERGENCE] Label generation failed: #{e.message}"
    nil
  end
end
