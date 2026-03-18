class NarrativeSignature < ApplicationRecord
  has_neighbors :centroid

  has_many :narrative_signature_articles, dependent: :destroy
  has_many :articles, through: :narrative_signature_articles

  scope :active,  -> { where(active: true) }
  scope :recent,  -> { order(last_seen_at: :desc) }
  scope :dormant, -> { where(last_seen_at: ..30.days.ago) }

  validates :label, presence: true

  THREAT_PRIORITY = %w[CRITICAL HIGH MODERATE LOW NEGLIGIBLE].freeze

  # Recalculate centroid from current member articles
  def recompute_centroid!
    embeddings = articles.where.not(embedding: nil).pluck(:embedding)
    return if embeddings.empty?

    avg = embeddings.first.zip(*embeddings[1..]).map { |dims| dims.sum / dims.size.to_f }

    trust_scores = articles.joins(:ai_analysis)
                           .where(ai_analyses: { analysis_status: "complete" })
                           .pluck("ai_analyses.trust_score").compact
    threats = articles.joins(:ai_analysis).pluck("ai_analyses.threat_level").compact
    sources = articles.pluck(:source_name).compact.tally
    countries = articles.joins(:country).pluck("countries.name").compact.tally

    update!(
      centroid: avg,
      match_count: embeddings.size,
      avg_trust_score: trust_scores.any? ? (trust_scores.sum / trust_scores.size).round(1) : 0.0,
      dominant_threat_level: THREAT_PRIORITY.find { |t| threats.include?(t) } || "UNKNOWN",
      source_distribution: sources,
      country_distribution: countries
    )
  end
end
