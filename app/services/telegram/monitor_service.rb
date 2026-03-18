module Telegram
  class MonitorService
    def self.start
      new.start
    end

    def initialize
      @token = ENV['TELEGRAM_BOT_TOKEN']
      # Expected format: "-100123,-100456"
      @channels = ENV['TELEGRAM_MONITORING_CHANNELS'].to_s.split(',').map(&:strip)
    end

    def start
      return unless @token.present?

      Rails.logger.info "[TELEGRAM MONITOR] Starting bot listener for #{@channels.size} channels..."
      
      require 'telegram/bot'
      
      # Note: Bots generally can't 'listen' to all channels unless they are members.
      # This service is for the bot's own webhook/updates.
      # For public channel monitoring (OSINT), you typically need a USER session (Telethon/Pyrogram),
      # but we'll implement the bot receiver logic here as requested.

      Telegram::Bot::Client.run(@token) do |bot|
        bot.listen do |message|
          # Only process if from a monitored channel
          channel_id = message.chat.id.to_s
          
          if @channels.include?(channel_id) || monitored_channel_record_exists?(channel_id)
            process_message(channel_id, message)
          end
        end
      end
    rescue StandardError => e
      Rails.logger.error "[TELEGRAM MONITOR] Fatal error: #{e.message}"
      # In production, we'd add retry logic here
    end

    private

    def monitored_channel_record_exists?(id)
      TelegramChannel.active.exists?(channel_id: id)
    end

    def process_message(channel_id, message)
      # message_data format to match TelegramReceiverJob
      data = {
        "message_id" => message.message_id,
        "date" => message.date,
        "text" => message.text || message.caption,
        "views" => message.try(:views),
        "forwards" => message.try(:forwards)
      }

      TelegramReceiverJob.perform_later(channel_id, data)
    end
  end
end
