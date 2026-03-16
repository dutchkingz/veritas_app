# frozen_string_literal: true

# ---------------------------------------------------------------
# IntelligenceReportsController
#
# Provides:
#   GET /intelligence_reports/:id/status  → JSON status for polling
#   POST /intelligence_reports            → Enqueue a new analysis job
# ---------------------------------------------------------------
class IntelligenceReportsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_report, only: %i[show status]

  # POST /intelligence_reports
  def create
    @region = Region.find(params[:region_id])
    
    # DEDUPLICATION: Check if a report for this region is already in flight (last 10 mins)
    @report = IntelligenceReport.where(region: @region)
                                .where(status: ["pending", "processing"])
                                .where("created_at > ?", 10.minutes.ago)
                                .first

    if @report
      render json: { report_id: @report.id, status: @report.status, message: "Analysis already in progress" }, status: :ok
      return
    end

    @report = IntelligenceReport.create!(region: @region, status: "pending")
    RegionalAnalysisJob.perform_later(@report.id)

    render json: { report_id: @report.id, status: @report.status }, status: :created
  end

  # GET /intelligence_reports/:id
  def show
    @previous_report = IntelligenceReport
      .where(region: @report.region, status: "completed")
      .where.not(id: @report.id)
      .order(created_at: :desc)
      .first
    @delta = @report.delta_from(@previous_report)
  end

  # GET /intelligence_reports/:id/status
  def status
    render json: serialize_report(@report)
  end

  private

  def ensure_admin!
    return if current_user.admin?

    respond_to do |format|
      format.html { redirect_to root_path, alert: "Access Denied." }
      format.json { render json: { error: "Admin access required" }, status: :forbidden }
    end
  end

  def set_report
    @report = IntelligenceReport.find(params[:id])
  end

  def serialize_report(report)
    {
      id:          report.id,
      status:      report.status,
      region:      report.region.name,
      summary:     report.summary,
      article_ids: report.analyzed_article_ids,
      created_at:  report.created_at
    }
  end
end
