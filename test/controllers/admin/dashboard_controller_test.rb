require "test_helper"

class Admin::DashboardControllerTest < ActionDispatch::IntegrationTest
  test "unauthenticated users are redirected" do
    get admin_dashboard_path
    assert_response :redirect
  end

  test "non-admin users are redirected with Access Denied" do
    sign_in build_user(role: "user")
    get admin_dashboard_path
    assert_redirected_to root_path
    assert_equal "Access Denied.", flash[:alert]
  end

  test "admin users can access the dashboard" do
    sign_in build_user(role: "admin")
    get admin_dashboard_path
    assert_response :success
  end

  private

  def build_user(role:)
    User.create!(
      email: "#{role}-#{SecureRandom.hex}@example.com",
      password: "password",
      password_confirmation: "password",
      role: role,
      admin: (role == "admin")
    )
  end
end
