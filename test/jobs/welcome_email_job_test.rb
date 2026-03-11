require "test_helper"
require "test_helper"

require "ostruct"

class WelcomeEmailJobTest < ActiveJob::TestCase
  test "job calls the WelcomeEmailService with the user" do
    # Create the user directly
    user = User.create!(email: "test#{SecureRandom.hex}@example.com", password: "password", password_confirmation: "password", role: "user")

    # Create a simple mock to track if it was called
    mock_service_class = Class.new do
      class << self
        attr_accessor :called_with
        def call(user)
          @called_with = user
          true
        end
      end
    end

    Sendgrid.send(:remove_const, :WelcomeEmailService)
    Sendgrid.const_set(:WelcomeEmailService, mock_service_class)

    begin
      WelcomeEmailJob.perform_now(user.id)
      assert_equal user, mock_service_class.called_with
    ensure
      # Restore original class or leave it for the rest of tests (in tests this is risky without proper teardown, but okay for a simple stub)
      load "app/services/sendgrid/welcome_email_service.rb"
    end
  end
end
