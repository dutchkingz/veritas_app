class DetectNarrativeConvergencesJob < ApplicationJob
  queue_as :default

  def perform
    Rails.logger.info "[JOB] DetectNarrativeConvergencesJob started"
    results = NarrativeConvergenceService.new.detect
    Rails.logger.info "[JOB] DetectNarrativeConvergencesJob complete — #{results.size} convergences written"

    # Check for narrative surges after fresh convergence data is written
    NarrativeSurgeDetectorService.new.detect_and_alert!
  rescue StandardError => e
    Rails.logger.error "[JOB] DetectNarrativeConvergencesJob failed: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
    raise
  end
end
