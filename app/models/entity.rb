class Entity < ApplicationRecord
  TYPES = %w[person organization country event].freeze

  TYPE_COLORS = {
    "person"       => "#38bdf8",  # cyan
    "organization" => "#a78bfa",  # purple
    "country"      => "#22c55e",  # green
    "event"        => "#f59e0b"   # amber
  }.freeze

  has_many :entity_mentions, dependent: :destroy
  has_many :articles, through: :entity_mentions

  validates :name,            presence: true
  validates :entity_type,     presence: true, inclusion: { in: TYPES }
  validates :normalized_name, presence: true, uniqueness: { scope: :entity_type }

  scope :by_type,         ->(type)    { where(entity_type: type) }
  scope :top_by_mentions, ->(n = 50)  { order(mentions_count: :desc).limit(n) }
  scope :with_min_mentions, ->(n = 2) { where("mentions_count >= ?", n) }

  def color
    TYPE_COLORS.fetch(entity_type, "#64748b")
  end

  # Canonical find-or-create with normalisation — prevents duplicates from
  # LLM variation in casing / punctuation.
  def self.find_or_create_normalized(name:, entity_type:)
    return nil unless TYPES.include?(entity_type.to_s)

    normalized = normalize(name)
    return nil if normalized.blank?

    find_or_create_by!(normalized_name: normalized, entity_type: entity_type.to_s) do |e|
      e.name          = name.strip
      e.first_seen_at = Time.current
    end
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    # Race condition safety — retry find
    find_by(normalized_name: normalize(name), entity_type: entity_type.to_s)
  end

  def self.normalize(name)
    name.to_s
        .strip
        .downcase
        .gsub(/[^a-z0-9\s\-']/, "")
        .squish
  end
end
