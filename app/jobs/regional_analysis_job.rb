# frozen_string_literal: true

# ---------------------------------------------------------------
# RegionalAnalysisJob
#
# Background job that invokes RegionalAnalysisService for a
# given IntelligenceReport. Designed to run via Solid Queue
# (the Rails 8 default) or any ActiveJob adapter.
#
# Enqueue with:
#   RegionalAnalysisJob.perform_later(report.id)
#
# ---------------------------------------------------------------
class RegionalAnalysisJob < ApplicationJob
  queue_as :default

  retry_on StandardError, wait: :polynomially_longer, attempts: 3

  def perform(report_id)
    report = IntelligenceReport.find_by(id: report_id)
    return unless report
    
    # Final safety check before processing
    return if report.completed? || report.processing?

    RegionalAnalysisService.call(report)
  rescue ActiveRecord::RecordNotFound
    Rails.logger.error("RegionalAnalysisJob: Report #{report_id} not found")
  end
end
