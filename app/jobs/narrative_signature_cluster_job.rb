class NarrativeSignatureClusterJob < ApplicationJob
  queue_as :intelligence

  COSINE_THRESHOLD = 0.18
  MIN_SEED_CLUSTER = 3
  MAX_ARTICLES     = 300
  LOOKBACK_DAYS    = 14

  def perform
    Rails.logger.info "[SIGNATURE CLUSTER] Starting signature creation from unmatched articles..."

    unmatched = load_unmatched_articles
    Rails.logger.info "[SIGNATURE CLUSTER] #{unmatched.size} unmatched articles found"
    return if unmatched.size < MIN_SEED_CLUSTER

    clusters = build_clusters(unmatched)
    qualifying = clusters.select { |c| c.size >= MIN_SEED_CLUSTER }
    Rails.logger.info "[SIGNATURE CLUSTER] #{qualifying.size} qualifying clusters"

    client = OpenRouterClient.new

    qualifying.each do |cluster|
      create_signature(cluster, client)
    end
  end

  private

  def load_unmatched_articles
    already_matched = NarrativeSignatureArticle.pluck(:article_id)

    scope = Article
      .joins(:ai_analysis)
      .where(published_at: LOOKBACK_DAYS.days.ago..)
      .where.not(embedding: nil)
      .where(ai_analyses: { analysis_status: "complete" })
      .includes(:ai_analysis, :country)
      .order(published_at: :desc)
      .limit(MAX_ARTICLES)

    scope = scope.where.not(id: already_matched) if already_matched.any?
    scope.to_a
  end

  # Union-Find clustering (same pattern as NarrativeConvergenceService)
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
             .limit(20)
             .each do |neighbor|
        union.(article.id, neighbor.id) if neighbor.neighbor_distance < COSINE_THRESHOLD
      end
    end

    article_map = articles.index_by(&:id)
    clusters = Hash.new { |h, k| h[k] = [] }
    articles.each { |a| clusters[find_root.(a.id)] << a }
    clusters.values
  end

  def create_signature(cluster, client)
    # Generate label
    headlines = cluster.first(6).map { |a| "- #{a.headline}" }.join("\n")
    system_prompt = <<~SYS
      You are an intelligence analyst. Given these news headlines from a detected narrative cluster,
      produce a single 3-7 word topic label in ALL CAPS that captures the core geopolitical narrative.
      Output ONLY the label — no punctuation, no explanation, nothing else.
    SYS
    label = client.chat(:arbiter, system_prompt, headlines, expect_json: false)&.strip
    label = label&.upcase&.gsub(/[^A-Z0-9 ]/, '')&.strip
    return if label.blank?

    # Compute centroid
    embeddings = cluster.select { |a| a.embedding.present? }.map(&:embedding)
    return if embeddings.size < MIN_SEED_CLUSTER

    centroid = embeddings.first.zip(*embeddings[1..]).map { |dims| dims.sum / dims.size.to_f }

    now = Time.current
    signature = NarrativeSignature.create!(
      label: label,
      centroid: centroid,
      match_count: cluster.size,
      first_seen_at: cluster.min_by(&:published_at).published_at || now,
      last_seen_at: cluster.max_by(&:published_at).published_at || now
    )

    cluster.each do |article|
      NarrativeSignatureArticle.create!(
        narrative_signature: signature,
        article: article,
        cosine_distance: 0.0,
        matched_at: now
      )
    end

    signature.recompute_centroid!

    Rails.logger.info "[SIGNATURE CLUSTER] ✓ Created '#{label}' — #{cluster.size} articles"
  rescue StandardError => e
    Rails.logger.error "[SIGNATURE CLUSTER] Failed to create signature: #{e.message}"
  end
end
