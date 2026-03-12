class FeaturePreviewsController < ApplicationController
  before_action :set_feature_name

  def index
    respond_feature_unavailable
  end

  def show
    respond_feature_unavailable
  end

  private

  def set_feature_name
    @feature_name = params[:feature].to_s.humanize.presence || "This feature"
  end

  def respond_feature_unavailable
    respond_to do |format|
      format.html { redirect_to root_path, alert: "#{@feature_name} is not production-ready yet." }
      format.json { render json: { error: "#{@feature_name} is not production-ready yet." }, status: :not_implemented }
    end
  end
end
