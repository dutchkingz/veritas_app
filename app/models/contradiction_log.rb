class ContradictionLog < ApplicationRecord
  belongs_to :article_a, class_name: "Article"
  belongs_to :article_b, class_name: "Article"

  TYPES = %w[self_contradiction cross_source temporal_shift].freeze

  validates :contradiction_type, inclusion: { in: TYPES }

  scope :severe,              -> { where(severity: 0.7..1.0) }
  scope :self_contradictions, -> { where(contradiction_type: "self_contradiction") }
  scope :cross_source,        -> { where(contradiction_type: "cross_source") }
  scope :temporal_shifts,     -> { where(contradiction_type: "temporal_shift") }
  scope :recent,              -> { order(created_at: :desc) }
end
