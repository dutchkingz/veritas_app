# frozen_string_literal: true

# ---------------------------------------------------------------
# ScheduleRegionalAnalysisJob
#
# Triggered by Solid Queue recurring schedule every 6 hours.
# Iterates over all regions and queues RegionalAnalysisJob for
# any region that doesn't have a recent completed report.
#
# Skips regions that already have a report generated within the
# last 6 hours to avoid duplicate runs on overlapping schedules.
# ---------------------------------------------------------------
class ScheduleRegionalAnalysisJob < ApplicationJob
  queue_as :default

  REFRESH_INTERVAL_HOURS = 6

  def perform
    Region.find_each do |region|
      next if recent_report_exists?(region)

      report = IntelligenceReport.create!(region: region, status: "pending")
      RegionalAnalysisJob.perform_later(report.id)

      Rails.logger.info "[ScheduleRegionalAnalysis] Queued report ##{report.id} for #{region.name}"
    end
  end

  private

  def recent_report_exists?(region)
    IntelligenceReport
      .where(region: region, status: %w[pending processing completed])
      .where("created_at > ?", REFRESH_INTERVAL_HOURS.hours.ago)
      .exists?
  end
end
