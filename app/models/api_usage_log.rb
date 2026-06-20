class ApiUsageLog < ApplicationRecord
  scope :today, -> { where("created_at >= ?", Time.current.beginning_of_day) }
  scope :successful, -> { where(status: "success") }
  scope :failed, -> { where(status: "error") }
  scope :by_model, -> { group(:model) }

  def self.total_cost_today
    today.sum(:estimated_cost).to_f
  end
end
