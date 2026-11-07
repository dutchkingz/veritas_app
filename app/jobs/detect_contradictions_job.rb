class DetectContradictionsJob < ApplicationJob
  queue_as :intelligence

  def perform
    if VeritasMode.demo?
      Rails.logger.info "[DetectContradictionsJob] Demo mode — skipping."
      return
    end

    ContradictionDetectionService.new.detect
  end
end
