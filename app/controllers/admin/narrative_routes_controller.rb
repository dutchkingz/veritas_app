module Admin
  class NarrativeRoutesController < ApplicationController
    before_action :authenticate_user!
    before_action :require_admin!
    
    # POST /admin/narrative_routes/generate
    def generate
      limit = params[:limit]&.to_i || 50
      
      # Enqueue the job
      job = GenerateNarrativeRoutesJob.perform_later(limit: limit)
      
      render json: {
        success: true,
        message: "Narrative route generation started",
        job_id: job.job_id,
        limit: limit
      }
    rescue Pundit::NotAuthorizedError
      render json: { success: false, error: "Admin access required" }, status: 403
    rescue StandardError => e
      Rails.logger.error "Failed to start narrative route generation: #{e.message}"
      render json: { success: false, error: e.message }, status: 500
    end
    
    private
    
    def require_admin!
      authorize :admin, :manage?
    end
  end
end
