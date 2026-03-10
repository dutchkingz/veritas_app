# -------------------------------------------------------
# Add Pundit to your base controller.
# rescue_from handles unauthorized access gracefully.
# -------------------------------------------------------
class ApplicationController < ActionController::Base
  before_action :authenticate_user!
  include Pundit::Authorization

  layout :layout_by_resource

  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

  private

  def user_not_authorized
    flash[:alert] = "You are not authorized to perform this action."
    redirect_back(fallback_location: root_path)
  end

  def layout_by_resource
    if devise_controller?
      "devise"
    else
      "application"
    end
  end
end
