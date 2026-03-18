class TelegramReceiverJob < ApplicationJob
  queue_as :default

  def perform(channel_id, message_data)
    Rails.logger.info "[TELEGRAM] Receiving message from channel #{channel_id}..."
    
    Telegram::MessageProcessor.call(channel_id, message_data)
  rescue StandardError => e
    Rails.logger.error "[TELEGRAM] Error processing message from #{channel_id}: #{e.message}"
    raise e
  end
end
