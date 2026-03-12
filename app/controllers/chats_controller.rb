class ChatsController < ApplicationController
  def create
    @query = params[:message]
    
    if @query.blank?
      render json: { response: "Enter a query to access the RAG database." }, status: :bad_request
      return
    end

    begin
      rag_response = RagAgent.new.ask(@query)
      render json: { response: rag_response }
    rescue StandardError => e
      Rails.logger.error "[CHAT CONTROLLER] Error: #{e.message}"
      render json: { response: "An error occurred while connecting to the intelligence database." }, status: :internal_server_error
    end
  end
end
