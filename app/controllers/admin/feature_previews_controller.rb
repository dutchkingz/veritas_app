class Admin::FeaturePreviewsController < ApplicationController
  before_action :ensure_admin!
  before_action :set_feature_name

  def index
    respond_feature_unavailable
  end

  def show
    respond_feature_unavailable
  end

  def new
    respond_feature_unavailable
  end

  def create
    respond_feature_unavailable
  end

  def edit
    respond_feature_unavailable
  end

  def update
    respond_feature_unavailable
  end

  def destroy
    respond_feature_unavailable
  end

  private

  def ensure_admin!
    return if current_user&.admin?

    respond_to do |format|
      format.html { redirect_to root_path, alert: "Access Denied." }
      format.json { render json: { error: "Admin access required" }, status: :forbidden }
    end
  end

  def set_feature_name
    @feature_name = params[:feature].to_s.humanize.presence || "This admin feature"
  end

  def respond_feature_unavailable
    respond_to do |format|
      format.html { redirect_to root_path, alert: "#{@feature_name} is not production-ready yet." }
      format.json { render json: { error: "#{@feature_name} is not production-ready yet." }, status: :not_implemented }
    end
  end
end
