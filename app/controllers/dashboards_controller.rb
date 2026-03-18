class DashboardsController < ApplicationController
  def show
    @articles = Article.includes(:ai_analysis, :country).order(published_at: :desc).limit(50)
    @latest_reports = IntelligenceReport.completed.includes(:region).order(created_at: :desc).limit(20)

    # Unix timestamps for the timeline scrubber
    @timeline_min = Article.minimum(:published_at)&.to_i || 24.hours.ago.to_i
    @timeline_max = Article.maximum(:published_at)&.to_i || Time.current.to_i
  end
end
