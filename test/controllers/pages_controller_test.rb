require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest
  test "non admin users see regional analysis as locked" do
    Region.create!(name: "Europe")
    sign_in build_user(role: "user")

    get root_path

    assert_response :success
    assert_includes response.body, "LOCKED"
  end

  test "admin users can run regional analysis" do
    Region.create!(name: "Europe")
    sign_in build_user(role: "admin")

    get root_path

    assert_response :success
    assert_includes response.body, "RUN"
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
