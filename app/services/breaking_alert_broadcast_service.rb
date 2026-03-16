class BreakingAlertBroadcastService
  def initialize(alert)
    @alert = alert
  end

  def broadcast!
    payload = { type: "breaking_alert", alert: @alert.as_broadcast_payload }
    Rails.logger.info "[VERITAS] *** BREAKING ALERT BROADCAST FIRED *** #{@alert.severity.upcase}: #{@alert.headline}"
    ActionCable.server.broadcast("alerts", payload)
    Rails.logger.info "[VERITAS] *** BROADCAST COMPLETE *** alert_id=#{@alert.id}"
  end
end
