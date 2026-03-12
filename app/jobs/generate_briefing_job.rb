class GenerateBriefingJob < ApplicationJob
  queue_as :default

  def perform(user_id)
    user = User.find_by(id: user_id)
    return unless user

    BriefingService.new(user).generate
  rescue StandardError => e
    Rails.logger.error "[JOB] GenerateBriefingJob failed for user #{user_id}: #{e.message}"
    raise
  end
end
