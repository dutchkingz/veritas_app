class DetectContradictionsJob < ApplicationJob
  queue_as :intelligence

  def perform
    ContradictionDetectionService.new.detect
  end
end
