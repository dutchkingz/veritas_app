module Api
  # Stealth endpoint — triggers surge detection on demand.
  # No admin UI. Called via keyboard shortcut or hidden pixel.
  # Authenticated users only (not admin-gated by design — looks like a normal API call).
  class SurgeChecksController < ApplicationController
    def create
      force  = params[:force].present?
      alert  = NarrativeSurgeDetectorService.new.detect_and_alert!(force: force)

      if alert
        render json: { triggered: true, alert_id: alert.id, severity: alert.severity }, status: :ok
      else
        # Return 200 even when no surge — no client-side error to raise suspicion
        render json: { triggered: false, reason: "no_surge_detected" }, status: :ok
      end
    rescue StandardError => e
      Rails.logger.error "[SURGE CHECK] Failed: #{e.message}"
      render json: { triggered: false }, status: :ok
    end
  end
end
