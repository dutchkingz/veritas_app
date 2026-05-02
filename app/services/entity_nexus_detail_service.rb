# Builds detail JSON for a single entity node in the Entity Nexus panel.
#
# Usage:
#   EntityNexusDetailService.new(entity).call
#   Returns: Hash with entity details, connected entities, articles, sentiment

class EntityNexusDetailService
  def initialize(entity)
    @entity = entity
  end

  def call
    articles = @entity.articles
      .includes(:ai_analysis, :country)
      .order(published_at: :desc)
      .limit(8)

    article_ids = @entity.article_ids.first(50)
    connected = build_connected_entities(article_ids)
    sentiment = compute_sentiment_breakdown

    max_mentions = Entity.maximum(:mentions_count).to_f
    vol_score    = max_mentions > 0 ? (@entity.mentions_count.to_f / max_mentions) : 0
    power_index  = (vol_score * 60).round

    {
      id:                 @entity.id,
      name:               @entity.name,
      entity_type:        @entity.entity_type,
      color:              @entity.color,
      mentions_count:     @entity.mentions_count,
      power_index:        power_index,
      first_seen_at:      @entity.first_seen_at&.iso8601,
      connected_entities: connected,
      articles: articles.map { |a| {
        id:              a.id,
        headline:        a.headline,
        source_name:     a.source_name,
        published_at:    a.published_at&.iso8601,
        country:         a.country&.name,
        threat_level:    a.ai_analysis&.threat_level,
        sentiment_color: a.ai_analysis&.sentiment_color || "#6b7280"
      }},
      sentiment: sentiment
    }
  end

  private

  def build_connected_entities(article_ids)
    return [] unless article_ids.any?

    rows = Entity.joins(:entity_mentions)
                 .where(entity_mentions: { article_id: article_ids })
                 .where.not(id: @entity.id)
                 .group(:id, :name, :entity_type)
                 .order(Arel.sql("COUNT(*) DESC"))
                 .limit(5)
                 .select("entities.id, entities.name, entities.entity_type, COUNT(*) AS shared_count")

    rows.map { |r| { id: r.id.to_i, name: r.name, entity_type: r.entity_type, shared_articles: r.shared_count.to_i } }
  end

  def compute_sentiment_breakdown
    labels = @entity.articles
      .joins(:ai_analysis)
      .where.not(ai_analyses: { sentiment_label: nil })
      .pluck("ai_analyses.sentiment_label")
      .map { |l| l.to_s.downcase }

    total = labels.size.to_f
    return { positive: 0, neutral: 0, negative: 0 } if total.zero?

    positive = labels.count { |l| l.include?("positive") || l.include?("bullish") }
    negative = labels.count { |l| l.include?("negative") || l.include?("bearish") || l.include?("hostile") }
    neutral  = labels.size - positive - negative

    {
      positive: (positive / total * 100).round,
      neutral:  (neutral  / total * 100).round,
      negative: (negative / total * 100).round
    }
  end
end
