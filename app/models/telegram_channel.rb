class TelegramChannel < ApplicationRecord
  validates :channel_id, presence: true, uniqueness: true
  
  scope :active, -> { where(monitoring_active: true) }
end
