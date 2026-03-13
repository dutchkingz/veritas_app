class GlobeChannel < ApplicationCable::Channel
  def subscribed
    stream_from "globe"
  end

  def unsubscribed
    stop_all_streams
  end
end
