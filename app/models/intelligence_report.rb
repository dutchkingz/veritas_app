class IntelligenceReport < ApplicationRecord
  belongs_to :region

  # ----------------------------------------------------------
  # Status lifecycle: pending → processing → completed / failed
  # ----------------------------------------------------------
  STATUS_OPTIONS = %w[pending processing completed failed].freeze

  validates :status, inclusion: { in: STATUS_OPTIONS }
  validates :region, presence: true

  scope :pending,    -> { where(status: "pending") }
  scope :processing, -> { where(status: "processing") }
  scope :completed,  -> { where(status: "completed") }
  scope :failed,     -> { where(status: "failed") }

  # ----------------------------------------------------------
  # Helpers
  # ----------------------------------------------------------
  def pending?    = status == "pending"
  def processing? = status == "processing"
  def completed?  = status == "completed"
  def failed?     = status == "failed"
end
