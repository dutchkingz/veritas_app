class Users::SessionsController < Devise::SessionsController
  # GET /users/sign_in → redirect to root (welcome page has the login form)
  def new
    redirect_to root_path
  end
end
