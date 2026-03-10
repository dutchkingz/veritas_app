# -------------------------------------------------------
# Handles user access management in the admin namespace.
# -------------------------------------------------------
class Admin::UsersController < ApplicationController
  before_action :authenticate_user!
  before_action :set_user, only: %i[show edit update destroy]

  def index
    @users = policy_scope(User)
    authorize @users
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

  private

  def set_user
    @user = User.find(params[:id])
  end

  def user_params
    params.require(:user).permit(:email, :first_name, :last_name, :role)
  end
end
