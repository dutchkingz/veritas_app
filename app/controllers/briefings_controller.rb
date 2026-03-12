class BriefingsController < ApplicationController
  before_action :authenticate_user!

  def index
    @briefings = current_user.briefings.order(generated_at: :desc).limit(20)
    @latest    = @briefings.first
  end

  def show
    @briefing = current_user.briefings.find(params[:id])
  end

  def create
    existing = current_user.briefings.where('generated_at > ?', 10.minutes.ago).first
    if existing
      redirect_to briefing_path(existing), notice: "Briefing generated less than 10 minutes ago — showing latest."
      return
    end

    GenerateBriefingJob.perform_later(current_user.id)
    redirect_to briefings_path, notice: "Generating your intelligence briefing… refresh in ~15 seconds."
  end
end
