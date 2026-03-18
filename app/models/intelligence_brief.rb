class IntelligenceBrief < ApplicationRecord
  TYPES = %w[daily weekly alert].freeze

  validates :brief_type, inclusion: { in: TYPES }
  validates :title, presence: true

  scope :daily,    -> { where(brief_type: "daily") }
  scope :weekly,   -> { where(brief_type: "weekly") }
  scope :latest,   -> { order(created_at: :desc) }
  scope :complete, -> { where(status: "complete") }
end
