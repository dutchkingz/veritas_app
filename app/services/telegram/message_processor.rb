module Telegram
  class MessageProcessor
    def self.call(channel_id, message_data)
      new(channel_id, message_data).call
    end

    def initialize(channel_id, message_data)
      @channel_id = channel_id
      @message_data = message_data
      @channel = TelegramChannel.find_by(channel_id: channel_id)
    end

    def call
      return unless @channel&.monitoring_active?
      
      # 1. Check for duplicates
      message_id = @message_data["message_id"].to_s
      return if Article.exists?(source_type: :telegram, telegram_channel_id: @channel_id, telegram_message_id: message_id)

      # 2. Create Article
      article = Article.create!(
        source_type: :telegram,
        telegram_channel_id: @channel_id,
        telegram_message_id: message_id,
        content: @message_data["text"] || @message_data["caption"],
        headline: @message_data["text"]&.truncate(100) || "Telegram Post from #{@channel.title}",
        source_name: "Telegram: #{@channel.title}",
        published_at: Time.at(@message_data["date"]),
        telegram_views: @message_data["views"],
        telegram_forwards: @message_data["forwards"],
        # Default coordinates for global/unknown (to be refined by AnalysisPipeline)
        latitude: 0,
        longitude: 0,
        region_id: @channel.topic.present? ? find_region_by_topic(@channel.topic) : default_region_id
      )

      # 3. Trigger Analysis Pipeline
      AnalyzeArticleJob.perform_later(article.id)
      
      article
    end

    private

    def find_region_by_topic(topic)
      # Basic heuristic or lookup
      Region.find_by("name ILIKE ?", "%#{topic}%")&.id || default_region_id
    end

    def default_region_id
      @default_region_id ||= Region.find_by(name: "Global")&.id || Region.first&.id
    end
  end
end
