class WelcomeEmailJob < ApplicationJob
  queue_as :default

  # Retry up to 3 times with exponential backoff (5s, 25s, 125s) before giving up
  retry_on StandardError, wait: :polynomially_longer, attempts: 3

  def perform(user_id)
    user = User.find_by(id: user_id)

    unless user
      Rails.logger.warn("[WelcomeEmailJob] Skipping — User ##{user_id} not found.")
      return
    end

    Rails.logger.info("[WelcomeEmailJob] Sending welcome email to #{user.email}...")
    success = Sendgrid::WelcomeEmailService.call(user)

    unless success
      Rails.logger.error("[WelcomeEmailJob] FAILED to send welcome email to #{user.email}. Will retry.")
      raise "SendGrid delivery failed for user ##{user_id} (#{user.email})"
    end

    Rails.logger.info("[WelcomeEmailJob] Welcome email delivered to #{user.email}.")
  end
end
