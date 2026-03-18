class EmbeddingSnapshot < ApplicationRecord
  scope :recent, -> { order(captured_at: :desc) }

  def previous
    self.class.where(captured_at: ...captured_at).order(captured_at: :desc).first
  end
end
