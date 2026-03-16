namespace :breaking_alert do
  desc "Run surge detection and fire alert if threshold met"
  task detect: :environment do
    puts "[VERITAS] Running NarrativeSurgeDetectorService..."
    alert = NarrativeSurgeDetectorService.new.detect_and_alert!
    if alert
      puts "[VERITAS] Alert fired: #{alert.severity.upcase} — #{alert.headline}"
    else
      puts "[VERITAS] No surge detected or cooldown active."
    end
  end

  desc "Broadcast the most recent active alert again (for testing WebSocket delivery)"
  task rebroadcast: :environment do
    alert = BreakingAlert.live.order(created_at: :desc).first
    if alert
      BreakingAlertBroadcastService.new(alert).broadcast!
      puts "[VERITAS] Rebroadcast: #{alert.headline}"
    else
      puts "[VERITAS] No active alerts to rebroadcast."
    end
  end
end
