class ModelConfigsController < ApplicationController
  before_action :authenticate_user!

  def show
    @config = current_user.effective_model_config
  end

  def update
    @config = current_user.model_config || current_user.build_model_config
    if @config.update(config_params)
      redirect_to dashboard_path, notice: "AI model configuration updated successfully."
    else
      render :show, status: :unprocessable_entity
    end
  end

  private

  def config_params
    params.require(:user_model_config).permit(
      :analyst_model,
      :sentinel_model,
      :arbiter_model,
      :briefing_model,
      :voice_model,
      :use_custom_endpoint,
      :custom_endpoint_url,
      :custom_api_key_encrypted
    )
  end
end
