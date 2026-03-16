class AlertsChannel < ApplicationCable::Channel
  def subscribed
    stream_from "alerts"
  end

  def unsubscribed
    stop_all_streams
  end
end
