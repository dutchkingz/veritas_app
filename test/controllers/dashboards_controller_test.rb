require "test_helper"

class DashboardsControllerTest < ActionDispatch::IntegrationTest
  test "should get show" do
    sign_in User.create!(email: "test#{SecureRandom.hex}@example.com", password: "password", password_confirmation: "password")
    get dashboards_show_url
    assert_response :success
  end
end
