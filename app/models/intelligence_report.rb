class IntelligenceReport < ApplicationRecord
  belongs_to :region

  # ----------------------------------------------------------
  # Status lifecycle: pending → processing → completed / failed
  # ----------------------------------------------------------
  STATUS_OPTIONS = %w[pending processing completed failed].freeze
  VALID_VERDICTS = %w[STABLE GUARDED ELEVATED SEVERE].freeze

  VERDICT_COLORS = {
    "STABLE"   => "#22c55e",
    "GUARDED"  => "#facc15",
    "ELEVATED" => "#f97316",
    "SEVERE"   => "#ef4444"
  }.freeze

  # Numeric rank for delta direction (higher = more dangerous)
  VERDICT_RANK = VALID_VERDICTS.each_with_index.to_h.freeze

  validates :status, inclusion: { in: STATUS_OPTIONS }
  validates :region, presence: true

  scope :pending,    -> { where(status: "pending") }
  scope :processing, -> { where(status: "processing") }
  scope :completed,  -> { where(status: "completed") }
  scope :failed,     -> { where(status: "failed") }
  scope :latest_for_region, ->(region_id) {
    where(region_id: region_id, status: "completed").order(created_at: :desc).first
  }

  # ----------------------------------------------------------
  # Status helpers
  # ----------------------------------------------------------
  def pending?    = status == "pending"
  def processing? = status == "processing"
  def completed?  = status == "completed"
  def failed?     = status == "failed"

  def verdict_color
    VERDICT_COLORS[verdict] || "#64748b"
  end

  def verdict_rank
    VERDICT_RANK[verdict] || 0
  end

  # ----------------------------------------------------------
  # Signal stats accessors (safe reads from jsonb)
  # ----------------------------------------------------------
  def stats
    signal_stats || {}
  end

  def stat(key, fallback = nil)
    stats[key.to_s] || fallback
  end

  def temporal_buckets
    stats["temporal_buckets"] || []
  end

  def top_sources
    stats["top_sources"] || []
  end

  # ----------------------------------------------------------
  # Historical delta — compares this report to a previous one.
  # Returns nil if no previous report or no signal_stats.
  # ----------------------------------------------------------
  def delta_from(previous)
    return nil unless previous&.signal_stats.present? && signal_stats.present?

    prev = previous.signal_stats
    curr = signal_stats

    trust_delta   = curr["avg_trust"].to_f - prev["avg_trust"].to_f
    anomaly_delta = curr["anomaly_count"].to_i - prev["anomaly_count"].to_i
    high_delta    = curr["high_count"].to_i - prev["high_count"].to_i
    source_delta  = curr["source_diversity"].to_i - prev["source_diversity"].to_i

    verdict_changed   = verdict != previous.verdict
    rank_diff         = verdict_rank - previous.verdict_rank
    direction         = rank_diff.positive? ? :escalating : (rank_diff.negative? ? :de_escalating : :stable)

    {
      previous_verdict:  previous.verdict,
      current_verdict:   verdict,
      verdict_changed:   verdict_changed,
      direction:         direction,
      trust_delta:       trust_delta.round(1),
      anomaly_delta:     anomaly_delta,
      high_delta:        high_delta,
      source_delta:      source_delta,
      previous_age:      previous.created_at
    }
  end
end
