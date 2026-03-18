class ContradictionDetectionService
  SIMILARITY_THRESHOLD = 0.12  # cosine distance — very similar articles (same topic)
  LOOKBACK_DAYS = 30
  MAX_PER_SOURCE = 50          # cap articles per source to avoid runaway queries

  def initialize
    @client = OpenRouterClient.new
  end

  def detect
    Rails.logger.info "[CONTRADICTION] Detection run started at #{Time.current}"

    self_count = detect_self_contradictions
    temporal_count = detect_temporal_shifts

    Rails.logger.info "[CONTRADICTION] Detection complete: #{self_count} self-contradictions, #{temporal_count} temporal shifts"
  end

  private

  def detect_self_contradictions
    count = 0

    sources = Article.where(published_at: LOOKBACK_DAYS.days.ago..)
                     .where.not(embedding: nil)
                     .distinct.pluck(:source_name).compact

    sources.each do |source|
      articles = Article.where(source_name: source, published_at: LOOKBACK_DAYS.days.ago..)
                        .where.not(embedding: nil)
                        .joins(:ai_analysis)
                        .where(ai_analyses: { analysis_status: "complete" })
                        .includes(:ai_analysis)
                        .order(published_at: :desc)
                        .limit(MAX_PER_SOURCE)

      next if articles.size < 2

      articles.each do |article|
        neighbors = article.nearest_neighbors(:embedding, distance: "cosine")
                           .where(source_name: source)
                           .where.not(id: article.id)
                           .limit(5)

        neighbors.each do |neighbor|
          next if neighbor.neighbor_distance > SIMILARITY_THRESHOLD
          next unless sentiment_opposes?(article, neighbor)
          next if contradiction_exists?(article, neighbor)

          log_contradiction(article, neighbor, "self_contradiction", neighbor.neighbor_distance)
          count += 1
        end
      end
    end

    count
  end

  def detect_temporal_shifts
    count = 0

    sources = Article.where(published_at: LOOKBACK_DAYS.days.ago..)
                     .where.not(embedding: nil)
                     .distinct.pluck(:source_name).compact

    sources.each do |source|
      articles = Article.where(source_name: source, published_at: LOOKBACK_DAYS.days.ago..)
                        .where.not(embedding: nil)
                        .joins(:ai_analysis)
                        .where(ai_analyses: { analysis_status: "complete" })
                        .includes(:ai_analysis)
                        .order(published_at: :asc)
                        .limit(MAX_PER_SOURCE)

      next if articles.size < 2

      articles.each do |article|
        neighbors = article.nearest_neighbors(:embedding, distance: "cosine")
                           .where(source_name: source)
                           .where.not(id: article.id)
                           .where("published_at > ?", article.published_at)
                           .limit(5)

        neighbors.each do |neighbor|
          next if neighbor.neighbor_distance > SIMILARITY_THRESHOLD
          next unless threat_shifted?(article, neighbor)
          next if contradiction_exists?(article, neighbor)

          log_contradiction(article, neighbor, "temporal_shift", neighbor.neighbor_distance)
          count += 1
        end
      end
    end

    count
  end

  def sentiment_opposes?(a, b)
    return false unless a.ai_analysis&.sentiment_label && b.ai_analysis&.sentiment_label
    sentiments = [a.ai_analysis.sentiment_label.downcase, b.ai_analysis.sentiment_label.downcase]
    (sentiments.include?("positive") && sentiments.include?("negative")) ||
      (sentiments.include?("supportive") && sentiments.include?("critical"))
  end

  def threat_shifted?(a, b)
    return false unless a.ai_analysis&.threat_level && b.ai_analysis&.threat_level
    levels = %w[NEGLIGIBLE LOW MODERATE HIGH CRITICAL]
    idx_a = levels.index(a.ai_analysis.threat_level.upcase) || 2
    idx_b = levels.index(b.ai_analysis.threat_level.upcase) || 2
    (idx_a - idx_b).abs >= 2  # at least 2 levels apart
  end

  def contradiction_exists?(a, b)
    ContradictionLog.exists?(article_a: a, article_b: b) ||
      ContradictionLog.exists?(article_a: b, article_b: a)
  end

  def log_contradiction(article_a, article_b, type, distance)
    description = generate_description(article_a, article_b, type)

    ContradictionLog.create!(
      article_a: article_a,
      article_b: article_b,
      contradiction_type: type,
      description: description,
      severity: (1.0 - distance).round(3),
      embedding_similarity: (1.0 - distance).round(3),
      source_a: article_a.source_name,
      source_b: article_b.source_name
    )

    Rails.logger.info "[CONTRADICTION] #{type}: '#{article_a.headline.truncate(50)}' vs '#{article_b.headline.truncate(50)}' — severity #{(1.0 - distance).round(2)}"
  end

  def generate_description(article_a, article_b, type)
    prompt = <<~PROMPT
      Article A: "#{article_a.headline}" (#{article_a.source_name}, #{article_a.published_at&.strftime('%Y-%m-%d')})
      Summary A: #{article_a.ai_analysis&.summary}
      Sentiment A: #{article_a.ai_analysis&.sentiment_label}
      Threat A: #{article_a.ai_analysis&.threat_level}

      Article B: "#{article_b.headline}" (#{article_b.source_name}, #{article_b.published_at&.strftime('%Y-%m-%d')})
      Summary B: #{article_b.ai_analysis&.summary}
      Sentiment B: #{article_b.ai_analysis&.sentiment_label}
      Threat B: #{article_b.ai_analysis&.threat_level}

      Type: #{type}
    PROMPT

    system = "You are an intelligence analyst. In 1-2 sentences, explain the contradiction between these two articles. Be specific about what changed or conflicts."

    @client.chat(:arbiter, system, prompt, expect_json: false)&.strip
  rescue StandardError => e
    Rails.logger.error "[CONTRADICTION] Description generation failed: #{e.message}"
    nil
  end
end
