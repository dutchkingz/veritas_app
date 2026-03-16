# -------------------------------------------------------
# Handles user access management in the admin namespace.
# -------------------------------------------------------
class Admin::UsersController < ApplicationController
  before_action :authenticate_user!
  before_action :set_user, only: %i[show edit update destroy toggle_admin]

  def index
    @users = policy_scope(User)
    authorize @users
  end

  def toggle_admin
    authorize @user
    
    # Toggle the admin boolean
    @user.admin = !@user.admin
    # Ensure role string also updates for consistency if app uses it
    @user.role = @user.admin ? "admin" : "user"
    
    if @user.save
      redirect_to admin_users_path, notice: "User status updated: #{@user.email} is now #{@user.admin ? 'an Admin' : 'a User'}."
    else
      redirect_to admin_users_path, alert: "Failed to update user status."
    end
  end

  def show
    authorize @user
  end

  def edit
    authorize @user
  end

  def update
    authorize @user
    if @user.update(user_params)
      redirect_to admin_users_path, notice: "User role updated successfully."
    else
      render :edit
    end
  end

  def destroy
    authorize @user
    @user.destroy
    redirect_to admin_users_path, notice: "User deleted successfully."
  end

  def invite
    authorize User, :index?
    email = params[:email].to_s.strip
    
    if email.present? && email.match?(URI::MailTo::EMAIL_REGEXP)
      success = Sendgrid::InvitationEmailService.call(email)
      if success
        redirect_to admin_users_path, notice: "Invitation sent to #{email} via SendGrid."
      else
        redirect_to admin_users_path, alert: "Failed to deliver invitation to #{email}. Check system logs."
      end
    else
      redirect_to admin_users_path, alert: "Please provide a valid email address."
    end
  end

  private

  def set_user
    @user = User.find(params[:id])
  end

  def user_params
    params.require(:user).permit(:email, :first_name, :last_name, :role)
  end
end
