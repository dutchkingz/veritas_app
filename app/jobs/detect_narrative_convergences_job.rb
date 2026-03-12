class DetectNarrativeConvergencesJob < ApplicationJob
  queue_as :default

  def perform
    Rails.logger.info "[JOB] DetectNarrativeConvergencesJob started"
    results = NarrativeConvergenceService.new.detect
    Rails.logger.info "[JOB] DetectNarrativeConvergencesJob complete — #{results.size} convergences written"
  rescue StandardError => e
    Rails.logger.error "[JOB] DetectNarrativeConvergencesJob failed: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
    raise
  end
end
