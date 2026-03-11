require "test_helper"

class UserTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "welcome email job is enqueued on user creation" do
    assert_enqueued_with(job: WelcomeEmailJob) do
      User.create!(email: "test_new_user#{SecureRandom.hex}@example.com", password: "password", password_confirmation: "password", role: "user")
    end
  end
end
