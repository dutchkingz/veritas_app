class ChatsController < ApplicationController
  def create
    @query = params[:message]

    if @query.blank?
      render json: { response: "Enter a query to access the RAG database.", sources: [] }, status: :bad_request
      return
    end

    history = session[:rag_history] || []

    begin
      voice_mode = params[:format_mode] == "voice_briefing"
      result = RagAgent.new(user: current_user).ask(
        @query,
        history: history,
        perspective_id: params[:perspective_id],
        voice_briefing: voice_mode
      )

      history << { role: "user",      content: @query.truncate(500) }
      history << { role: "assistant", content: result[:response].truncate(500) }
      session[:rag_history] = history.last(6)

      render json: result
    rescue StandardError => e
      Rails.logger.error "[CHAT CONTROLLER] Error: #{e.message}"
      render json: { response: "An error occurred while connecting to the intelligence database.", sources: [] },
             status: :internal_server_error
    end
  end
end
