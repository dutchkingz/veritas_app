class CaptureEmbeddingSnapshotJob < ApplicationJob
  queue_as :intelligence

  def perform
    if VeritasMode.demo?
      Rails.logger.info "[CaptureEmbeddingSnapshotJob] Demo mode — skipping."
      return
    end

    EmbeddingDriftService.new.capture_snapshot
  end
end
