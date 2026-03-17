class BreakingAlert < ApplicationRecord
  belongs_to :region,       optional: true
  belongs_to :triggered_by, class_name: "User", optional: true

  enum :severity, { critical: 0, high: 1, elevated: 2, moderate: 3 }
  enum :status,   { active: 0, acknowledged: 1, expired: 2 }

  validates :headline, presence: true, length: { maximum: 120 }
  validates :briefing, presence: true, length: { maximum: 600 }
  validates :lat, presence: true, numericality: { greater_than_or_equal_to: -90, less_than_or_equal_to: 90 }
  validates :lng, presence: true, numericality: { greater_than_or_equal_to: -180, less_than_or_equal_to: 180 }

  scope :live,   -> { active.where("expires_at IS NULL OR expires_at > ?", Time.current) }
  scope :recent, -> { order(created_at: :desc).limit(20) }

  after_create :broadcast_to_clients
  before_create :set_expiry

  SEVERITY_COLORS = {
    "critical" => "#ef4444",
    "high"     => "#f97316",
    "elevated" => "#f59e0b",
    "moderate" => "#00f0ff"
  }.freeze

  def color
    SEVERITY_COLORS[severity] || SEVERITY_COLORS["moderate"]
  end

  def region_name
    region&.name || metadata["region_name"] || "UNKNOWN REGION"
  end

  def as_broadcast_payload
    {
      id:           id,
      headline:     headline,
      briefing:     briefing,
      severity:     severity,
      color:        color,
      lat:          lat,
      lng:          lng,
      region_name:  region_name,
      source_count: metadata["sources_involved"] || 0,
      article_count: metadata["article_count"] || 0,
      triggered_at: created_at&.iso8601,
      expires_at:   expires_at&.iso8601
    }
  end

  private

  def set_expiry
    self.expires_at ||= 8.minutes.from_now
  end

  def broadcast_to_clients
    BreakingAlertBroadcastService.new(self).broadcast!
  end
end
