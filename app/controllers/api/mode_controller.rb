module Api
  class ModeController < ApplicationController
    skip_before_action :authenticate_user!, only: [:show]
    before_action :require_admin!, only: [:toggle]

    # GET /api/mode
    def show
      render json: mode_status
    end

    # POST /api/mode/toggle
    def toggle
      # If switching to live, validate API keys first
      if VeritasMode.demo? && !VeritasMode.live_mode_ready?
        missing = VeritasMode.missing_api_keys.join(", ")
        return render json: {
          error: "Cannot activate Live Mode — missing API keys: #{missing}. Check your environment variables.",
          mode: "demo"
        }, status: :unprocessable_entity
      end

      new_mode = VeritasMode.toggle!

      # Start the recurring fetch loop when switching to live
      FetchArticlesJob.perform_later if new_mode == "live"

      # If we just hit the API limit, auto-fallback to demo
      if new_mode == "live" && VeritasMode.api_limit_reached?
        VeritasMode.set!("demo")
        return render json: {
          error: "API daily limit reached. Falling back to Demo Mode.",
          **mode_status
        }
      end

      render json: mode_status
    end

    private

    def mode_status
      {
        mode: VeritasMode.current,
        api_calls_today: VeritasMode.api_calls_today,
        api_calls_remaining: VeritasMode.api_calls_remaining,
        live_ready: VeritasMode.live_mode_ready?
      }
    end
  end
end
