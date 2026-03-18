namespace :veritas do
  namespace :telegram do
    desc "Start the Telegram OSINT Monitoring Service"
    task monitor: :environment do
      puts "[VERITAS] INITIALIZING TELEGRAM MONITORING NODE..."
      Telegram::MonitorService.start
    end

    desc "Seed default intelligence channels"
    task seed_channels: :environment do
      channels = [
        { channel_id: "-1001234567890", title: "Intel Alpha", topic: "Middle East", username: "intel_alpha" },
        { channel_id: "-1009876543210", title: "Cyber Shield", topic: "Cybersecurity", username: "cyber_shield" }
      ]
      
      channels.each do |c|
        TelegramChannel.find_or_create_by!(channel_id: c[:channel_id]) do |tc|
          tc.title = c[:title]
          tc.topic = c[:topic]
          tc.username = c[:username]
          tc.monitoring_active = true
        end
      end
      puts "[VERITAS] SEEDED #{channels.size} TELEGRAM CHANNELS."
    end
  end
end
