class CaptureEmbeddingSnapshotJob < ApplicationJob
  queue_as :intelligence

  def perform
    EmbeddingDriftService.new.capture_snapshot
  end
end
