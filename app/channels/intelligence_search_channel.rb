class IntelligenceSearchChannel < ApplicationCable::Channel
  def subscribed
    stream_from "intelligence_search_#{params[:query]}"
  end

  def unsubscribed
    stop_all_streams
  end
end
