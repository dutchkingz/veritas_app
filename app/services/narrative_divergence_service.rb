# NarrativeDivergenceService
#
# Computes how far a given perspective's narrative framing diverges from the
# Western Mainstream baseline. Uses existing ai_analysis data — zero extra API calls.
#
# Formula:
#   1. Gather articles from active perspective (matched by SourceClassifierService)
#   2. Gather articles from Western Mainstream baseline
#   3. For each group: compute avg sentiment_polarity and avg trust_score
#   4. Divergence = normalized absolute difference (0–100%)
#   5. If fewer than MIN_ARTICLES in either group → :insufficient_data
#
# Usage:
#   NarrativeDivergenceService.new("china_state").compute
#   # => { score: 74, label: "HIGH", sentiment_delta: 0.6, trust_delta: 0.3, status: :ok }

class NarrativeDivergenceService
  MIN_ARTICLES     = 3
  BASELINE_SLUG    = "western_mainstream"

  def initialize(perspective_slug, topic: nil)
    @slug  = perspective_slug
    @topic = topic
  end

  def compute
    return { status: :no_op } if @slug == "all" || @slug == BASELINE_SLUG

    perspective_articles = articles_for_slug(@slug)
    baseline_articles    = articles_for_slug(BASELINE_SLUG)

    if perspective_articles.size < MIN_ARTICLES
      return { status: :insufficient_data, reason: "Need #{MIN_ARTICLES}+ articles for #{@slug}" }
    end

    if baseline_articles.size < MIN_ARTICLES
      return { status: :insufficient_data, reason: "Need #{MIN_ARTICLES}+ baseline articles" }
    end

    p_sentiment = avg_sentiment(perspective_articles)
    b_sentiment = avg_sentiment(baseline_articles)
    p_trust     = avg_trust(perspective_articles)
    b_trust     = avg_trust(baseline_articles)

    # Sentiment delta: -1..+1 range, normalize to 0..1
    sentiment_delta = (p_sentiment - b_sentiment).abs / 2.0
    # Trust delta: 0..100 range, normalize to 0..1
    trust_delta     = (p_trust - b_trust).abs / 100.0

    # Composite divergence: weight sentiment 60%, trust 40%
    raw_score = (sentiment_delta * 0.60) + (trust_delta * 0.40)
    score     = (raw_score * 100).round.clamp(0, 100)

    {
      status:          :ok,
      score:           score,
      label:           divergence_label(score),
      sentiment_delta: sentiment_delta.round(3),
      trust_delta:     trust_delta.round(3),
      p_articles:      perspective_articles.size,
      b_articles:      baseline_articles.size,
      p_avg_sentiment: p_sentiment.round(3),
      b_avg_sentiment: b_sentiment.round(3)
    }
  end

  private

  # Get articles matching the perspective slug, optionally filtered by topic keyword
  def articles_for_slug(slug)
    source_names = SourceClassifierService.sources_for(slug)
    return [] if source_names.empty?

    # Build case-insensitive ILIKE conditions for each source
    conditions = source_names.map { "LOWER(articles.source_name) LIKE ?" }.join(" OR ")
    values     = source_names.map { |s| "%#{s}%" }

    scope = Article
      .joins(:ai_analysis)
      .where(conditions, *values)
      .where.not(ai_analyses: { analysis_status: "pending" })

    scope = scope.where("articles.headline ILIKE ?", "%#{@topic}%") if @topic.present?

    scope.select("articles.id, ai_analyses.sentiment_label, ai_analyses.trust_score").limit(100).to_a
  end

  # Convert sentiment_label to numeric polarity: positive=+1, neutral=0, negative=-1
  def sentiment_polarity(label)
    case label.to_s.downcase
    when "positive", "bullish" then  1.0
    when "negative", "bearish" then -1.0
    else 0.0
    end
  end

  def avg_sentiment(articles)
    return 0.0 if articles.empty?
    articles.sum { |a| sentiment_polarity(a.sentiment_label) } / articles.size.to_f
  end

  def avg_trust(articles)
    scored = articles.select { |a| a.trust_score.present? }
    return 50.0 if scored.empty?
    scored.sum(&:trust_score) / scored.size.to_f
  end

  def divergence_label(score)
    if    score >= 75 then "CRITICAL"
    elsif score >= 50 then "HIGH"
    elsif score >= 25 then "MODERATE"
    else                   "LOW"
    end
  end
end
