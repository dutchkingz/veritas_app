class WelcomeEmailJob < ApplicationJob
  queue_as :default

  def perform(user_id)
    user = User.find_by(id: user_id)
    return unless user
    
    success = Sendgrid::WelcomeEmailService.call(user)
    
    raise "SendGrid Delivery Failed" unless success
  end
end
