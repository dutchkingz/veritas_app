class EmbeddingDriftService
  COSINE_THRESHOLD = 0.15
  MAX_ARTICLES     = 500
  LOOKBACK_DAYS    = 14

  def capture_snapshot
    Rails.logger.info "[DRIFT] Capturing embedding snapshot..."

    articles = Article.where(published_at: LOOKBACK_DAYS.days.ago..)
                      .where.not(embedding: nil)
                      .includes(:ai_analysis)
                      .order(published_at: :desc)
                      .limit(MAX_ARTICLES)

    return if articles.empty?

    clusters = build_clusters(articles)
    cluster_summary = summarize_clusters(clusters)
    outlier_ids = find_outliers(articles, clusters)
    drift_metrics = compute_drift(cluster_summary)

    EmbeddingSnapshot.create!(
      captured_at: Time.current,
      article_count: articles.size,
      cluster_count: clusters.size,
      cluster_summary: cluster_summary,
      drift_metrics: drift_metrics,
      outlier_ids: outlier_ids
    )

    Rails.logger.info "[DRIFT] Snapshot captured: #{articles.size} articles, #{clusters.size} clusters, #{outlier_ids.size} outliers"
  end

  private

  def build_clusters(articles)
    article_ids = articles.map(&:id)
    parent = article_ids.index_with { |id| id }

    find_root = ->(id) {
      while parent[id] != id
        parent[id] = parent[parent[id]]
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
             .limit(15)
             .each do |neighbor|
        union.(article.id, neighbor.id) if neighbor.neighbor_distance < COSINE_THRESHOLD
      end
    end

    article_map = articles.index_by(&:id)
    clusters = Hash.new { |h, k| h[k] = [] }
    articles.each { |a| clusters[find_root.(a.id)] << a }
    clusters.values.select { |c| c.size >= 2 }
  end

  def summarize_clusters(clusters)
    clusters.map do |cluster|
      sources = cluster.map(&:source_name).compact.tally
      threats = cluster.filter_map { |a| a.ai_analysis&.threat_level }.tally

      {
        size: cluster.size,
        top_sources: sources.sort_by { |_, v| -v }.first(5).to_h,
        dominant_threat: threats.max_by { |_, v| v }&.first || "UNKNOWN",
        avg_trust: cluster.filter_map { |a| a.ai_analysis&.trust_score }.then { |s| s.any? ? (s.sum / s.size).round(1) : 0 },
        oldest: cluster.min_by(&:published_at)&.published_at&.iso8601,
        newest: cluster.max_by(&:published_at)&.published_at&.iso8601
      }
    end.sort_by { |c| -c[:size] }
  end

  def find_outliers(articles, clusters)
    clustered_ids = clusters.flatten.map(&:id).to_set
    articles.reject { |a| clustered_ids.include?(a.id) }.map(&:id)
  end

  def compute_drift(current_summary)
    previous = EmbeddingSnapshot.recent.first
    return { status: "first_snapshot" } unless previous

    prev_clusters = previous.cluster_summary || []

    {
      previous_cluster_count: prev_clusters.size,
      current_cluster_count: current_summary.size,
      cluster_delta: current_summary.size - prev_clusters.size,
      previous_outliers: (previous.outlier_ids || []).size,
      hours_since_last: ((Time.current - previous.captured_at) / 1.hour).round(1)
    }
  end
end
