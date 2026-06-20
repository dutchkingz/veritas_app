class Admin::DashboardController < ApplicationController
  before_action :ensure_admin!

  def show
    @health = SystemHealthService.new.call
  end

  def fetch_articles
    FetchArticlesJob.perform_later
    redirect_to admin_dashboard_path, notice: "Article fetch job enqueued."
  end

  private

  def ensure_admin!
    return if current_user&.admin?

    respond_to do |format|
      format.html { redirect_to root_path, alert: "Access Denied." }
      format.json { render json: { error: "Admin access required" }, status: :forbidden }
    end
  end
end
