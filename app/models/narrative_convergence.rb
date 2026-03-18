class NarrativeConvergence < ApplicationRecord
  include ConfidenceScoreable
  # topic_keyword stores JSON metadata — see metadata accessors below
  # article_count         — number of articles in cluster
  # convergence_percentage — source diversity (unique sources / total * 100)
  # calculated_at         — when this convergence was detected

  scope :recent,  -> { order(calculated_at: :desc) }
  scope :active,  -> { where(calculated_at: 7.days.ago..) }

  THREAT_COLORS = {
    'CRITICAL' => '#ef4444',
    'HIGH'     => '#f97316',
    'MODERATE' => '#eab308',
    'LOW'      => '#22c55e',
    'UNKNOWN'  => '#64748b'
  }.freeze

  def metadata
    @metadata ||= JSON.parse(topic_keyword)
  rescue JSON::ParserError, TypeError
    { 'label' => topic_keyword.to_s }
  end

  def label               = metadata['label'] || 'UNKNOWN NARRATIVE'
  def article_ids         = metadata['article_ids'] || []
  def countries           = metadata['countries'] || []
  def source_names        = metadata['source_names'] || []
  def origin_article_id   = metadata['origin_article_id']
  def origin_country      = metadata['origin_country'] || 'UNKNOWN'
  def dominant_threat_level = metadata['dominant_threat_level'] || 'UNKNOWN'
  def avg_trust_score     = metadata['avg_trust_score'] || 0

  def threat_color
    THREAT_COLORS[dominant_threat_level] || THREAT_COLORS['UNKNOWN']
  end

  def articles
    Article.where(id: article_ids).includes(:ai_analysis, :country)
  end

  def age_label
    return 'Unknown' unless calculated_at
    hours = ((Time.current - calculated_at) / 1.hour).round
    hours < 1 ? 'Just now' : "#{hours}h ago"
  end
end
