class DashboardsController < ApplicationController
  def show
    @articles = Article.order(published_at: :desc).limit(50)
    @latest_reports = IntelligenceReport.completed.order(created_at: :desc).limit(20)
    
    # For the time slider initial state
    @timeline_min = Article.minimum(:published_at) || 24.hours.ago
    @timeline_max = Time.current
  end
end
