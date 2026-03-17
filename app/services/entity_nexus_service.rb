# EntityNexusService
#
# Builds the full Entity Nexus graph payload for the frontend:
#   - nodes:      top entities by Power Index with sparklines
#   - edges:      co-mention relationships (shared articles)
#   - top_actors: top 5 by Power Index for the sidebar panel
#   - meta:       summary stats
#
# Power Index (0-100) weights:
#   40% — Article volume (relative to max in result set)
#   25% — Cross-region spread (unique regions across mentioned articles)
#   20% — Threat association (avg threat_level of mentioned articles)
#   15% — Velocity (mentions last 12h vs 12-48h acceleration)
#
# Usage:
#   EntityNexusService.new.call
#   EntityNexusService.new(min_mentions: 3, entity_type: "person").call
#   EntityNexusService.new(article_id: 42).call  # scoped to one article

class EntityNexusService
  MAX_NODES       = 60
  MAX_EDGES       = 200
  SPARKLINE_SLOTS = 6   # 6 × 8h = 48h window

  def initialize(min_mentions: 1, entity_type: nil, article_id: nil)
    @min_mentions = min_mentions.to_i
    @entity_type  = entity_type.presence
    @article_id   = article_id.presence
  end

  def call
    entities = fetch_entities
    return empty_result if entities.empty?

    entity_ids     = entities.map(&:id)
    articles_by_entity = fetch_articles_by_entity(entity_ids)
    region_counts  = compute_region_counts(articles_by_entity)
    threat_avgs    = compute_threat_averages(articles_by_entity)
    velocities     = compute_velocities(entity_ids)
    sparklines     = compute_sparklines(entity_ids)
    max_mentions   = entities.map(&:mentions_count).max.to_f

    nodes = entities.map do |entity|
      power = power_index(
        mentions:  entity.mentions_count,
        max_mentions: max_mentions,
        regions:   region_counts[entity.id] || 0,
        threat:    threat_avgs[entity.id]   || 0,
        velocity:  velocities[entity.id]    || 0
      )

      {
        id:              entity.id,
        name:            entity.name,
        entity_type:     entity.entity_type,
        normalized_name: entity.normalized_name,
        mentions_count:  entity.mentions_count,
        power_index:     power,
        color:           entity.color,
        regions:         region_counts[entity.id] || 0,
        avg_threat:      (threat_avgs[entity.id] || 0).round(1),
        avg_sentiment_color: sentiment_color_for_threat(threat_avgs[entity.id] || 0),
        sparkline:       sparklines[entity.id] || Array.new(SPARKLINE_SLOTS, 0)
      }
    end

    nodes.sort_by! { |n| -n[:power_index] }
    edges = build_edges(entity_ids, nodes)

    {
      meta: {
        total_entities:  Entity.count,
        shown_entities:  nodes.size,
        total_mentions:  EntityMention.count,
        top_type:        dominant_type(nodes)
      },
      nodes:      nodes,
      edges:      edges,
      top_actors: nodes.first(5)
    }
  end

  private

  # ─── Data fetching ────────────────────────────────────────────────────────

  def fetch_entities
    scope = Entity.with_min_mentions(@min_mentions)
    scope = scope.by_type(@entity_type) if @entity_type
    scope = scope.joins(:entity_mentions).where(entity_mentions: { article_id: @article_id }) if @article_id
    scope.top_by_mentions(MAX_NODES)
  end

  def fetch_articles_by_entity(entity_ids)
    rows = EntityMention
      .where(entity_id: entity_ids)
      .joins(article: [:region, :ai_analysis])
      .pluck(:entity_id, "regions.name", "ai_analyses.threat_level")

    result = Hash.new { |h, k| h[k] = [] }
    rows.each do |(eid, region_name, threat)|
      result[eid] << { region: region_name, threat: threat.to_i }
    end
    result
  end

  # ─── Power Index components ───────────────────────────────────────────────

  def compute_region_counts(articles_by_entity)
    articles_by_entity.transform_values do |rows|
      rows.map { |r| r[:region] }.compact.uniq.size
    end
  end

  def compute_threat_averages(articles_by_entity)
    articles_by_entity.transform_values do |rows|
      threats = rows.map { |r| r[:threat] }.select(&:positive?)
      threats.any? ? (threats.sum.to_f / threats.size) : 0
    end
  end

  def compute_velocities(entity_ids)
    now        = Time.current
    recent_cut = now - 12.hours
    older_cut  = now - 48.hours

    recent_counts = EntityMention
      .where(entity_id: entity_ids)
      .joins(:article)
      .where("articles.published_at >= ?", recent_cut)
      .group(:entity_id)
      .count

    older_counts = EntityMention
      .where(entity_id: entity_ids)
      .joins(:article)
      .where("articles.published_at >= ? AND articles.published_at < ?", older_cut, recent_cut)
      .group(:entity_id)
      .count

    entity_ids.each_with_object({}) do |eid, hash|
      recent = recent_counts[eid] || 0
      older  = (older_counts[eid] || 0).to_f / 3  # normalize 36h window → ~12h equivalent
      hash[eid] = older > 0 ? ((recent - older) / older).clamp(-1, 3) : (recent > 0 ? 1.0 : 0)
    end
  end

  def compute_sparklines(entity_ids)
    now = Time.current
    slot_hours = 48.0 / SPARKLINE_SLOTS  # 8h per slot

    rows = EntityMention
      .where(entity_id: entity_ids)
      .joins(:article)
      .where("articles.published_at >= ?", 48.hours.ago)
      .pluck(:entity_id, "articles.published_at")

    # Group into time slots
    result = Hash.new { |h, k| h[k] = Array.new(SPARKLINE_SLOTS, 0) }
    rows.each do |(eid, pub_at)|
      next unless pub_at
      hours_ago = (now - pub_at) / 3600.0
      slot = ((48.0 - hours_ago) / slot_hours).floor.clamp(0, SPARKLINE_SLOTS - 1)
      result[eid][slot] += 1
    end
    result
  end

  def power_index(mentions:, max_mentions:, regions:, threat:, velocity:)
    vol_score      = max_mentions > 0 ? (mentions.to_f / max_mentions) : 0
    region_score   = [regions / 6.0, 1.0].min         # saturates at 6 regions
    threat_score   = threat / 10.0                     # threat 0-10 → 0-1
    velocity_score = [(velocity + 1) / 4.0, 1.0].min  # shift -1..3 → 0..1 range

    raw = (vol_score * 40) + (region_score * 25) + (threat_score * 20) + (velocity_score * 15)
    raw.round
  end

  # ─── Edge building (co-mention self-join) ─────────────────────────────────

  def build_edges(entity_ids, nodes)
    return [] if entity_ids.size < 2

    node_index = nodes.each_with_object({}) { |n, h| h[n[:id]] = n }

    sql = <<~SQL
      SELECT em1.entity_id AS source_id,
             em2.entity_id AS target_id,
             COUNT(*)      AS weight,
             AVG(CASE
               WHEN ai.threat_level ~ '^[0-9]+$' THEN ai.threat_level::integer
               WHEN ai.threat_level = 'CRITICAL'  THEN 9
               WHEN ai.threat_level = 'HIGH'       THEN 7
               WHEN ai.threat_level = 'MODERATE'   THEN 5
               WHEN ai.threat_level = 'LOW'         THEN 2
               ELSE 0
             END) AS avg_threat
      FROM entity_mentions em1
      JOIN entity_mentions em2
        ON em1.article_id = em2.article_id
       AND em1.entity_id  < em2.entity_id
      LEFT JOIN ai_analyses ai ON ai.article_id = em1.article_id
      WHERE em1.entity_id IN (#{entity_ids.join(',')})
        AND em2.entity_id IN (#{entity_ids.join(',')})
      GROUP BY em1.entity_id, em2.entity_id
      HAVING COUNT(*) >= 1
      ORDER BY weight DESC
      LIMIT #{MAX_EDGES}
    SQL

    rows = ActiveRecord::Base.connection.execute(sql)

    rows.map do |row|
      avg_threat = row["avg_threat"].to_f
      {
        source:              row["source_id"].to_i,
        target:              row["target_id"].to_i,
        weight:              row["weight"].to_i,
        avg_sentiment_color: sentiment_color_for_threat(avg_threat),
        hot:                 row["weight"].to_i >= 3
      }
    end
  end

  # ─── Helpers ──────────────────────────────────────────────────────────────

  def sentiment_color_for_threat(threat)
    case threat.to_f
    when 7..10 then "#ef4444"
    when 4..7  then "#f59e0b"
    when 1..4  then "#38bdf8"
    else             "#22c55e"
    end
  end

  def dominant_type(nodes)
    nodes.group_by { |n| n[:entity_type] }
         .max_by { |_, ns| ns.size }
         &.first || "person"
  end

  def empty_result
    {
      meta:       { total_entities: 0, shown_entities: 0, total_mentions: 0, top_type: "person" },
      nodes:      [],
      edges:      [],
      top_actors: []
    }
  end
end
