module Api
  class SearchSuggestionsController < ApplicationController
    # GET /api/search_suggestions?q=...
    def index
      query = params[:q].to_s.strip
      
      suggestions = if query.length >= 3
        # Search for matching topics from recent articles
        Article
          .joins(:ai_analysis)
          .where("ai_analyses.geopolitical_topic ILIKE ?", "%#{query}%")
          .distinct
          .pluck(:ai_analysis, :geopolitical_topic)
          .compact
          .uniq
          .first(5)
      else
        []
      end
      
      render json: {
        query: query,
        suggestions: suggestions
      }
    end
  end
end