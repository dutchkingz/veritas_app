module Telegram
  class AlertService
    def self.alert_admins(article, reason)
      new(article, reason).call
    end

    def initialize(article, reason)
      @article = article
      @reason  = reason
      @token   = ENV['TELEGRAM_BOT_TOKEN']
      @admin_chat_id = ENV['TELEGRAM_ADMIN_CHAT_ID']
    end

    def call
      return unless @token.present? && @admin_chat_id.present?

      message = build_alert_message
      send_telegram_dm(message)
    end

    private

    def build_alert_message
      threat_level = @article.ai_analysis&.threat_level || "UNKNOWN"
      
      <<~TEXT
        🚨 *HIGH THREAT SIGNAL DETECTED* 🚨
        
        *ID:* ##{@article.id}
        *SOURCE:* #{@article.source_name}
        *THREAT:* LVL_#{threat_level}
        *TOPIC:* #{@article.ai_analysis&.geopolitical_topic}
        
        *REASON:* #{@reason}
        
        *CONTENT:* 
        #{@article.headline.truncate(200)}
        
        *URL:* https://veritas-app-314a53c53525.herokuapp.com/articles/#{@article.id}
        
        📡 [VERITAS INTEL NODE]
      TEXT
    end

    def send_telegram_dm(message)
      require 'telegram/bot'
      
      Telegram::Bot::Client.run(@token) do |bot|
        bot.api.send_message(
          chat_id: @admin_chat_id,
          text: message,
          parse_mode: 'Markdown'
        )
      end
    rescue StandardError => e
      Rails.logger.error "[TELEGRAM ALERT] Failed to send alert to admin chat: #{e.message}"
    end
  end
end
