require "test_helper"

require "ostruct"

class WelcomeEmailJobTest < ActiveJob::TestCase
  test "job calls the WelcomeEmailService with the user" do
    user = User.create!(email: "test#{SecureRandom.hex}@example.com", password: "password", password_confirmation: "password", role: "user")

    mock_service_class = Class.new do
      class << self
        attr_accessor :called_with
        def call(user)
          @called_with = user
          true
        end
      end
    end

    ResendMail.send(:remove_const, :WelcomeEmailService)
    ResendMail.const_set(:WelcomeEmailService, mock_service_class)

    begin
      WelcomeEmailJob.perform_now(user.id)
      assert_equal user, mock_service_class.called_with
    ensure
      load "app/services/resend_mail/welcome_email_service.rb"
    end
  end
end
