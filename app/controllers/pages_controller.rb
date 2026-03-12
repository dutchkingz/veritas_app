class PagesController < ApplicationController
  def home
    @articles = Article.includes(:country, :region).order(published_at: :desc).limit(50)
    @regions  = Region.order(:name)
  end

  def search
    @query = params[:q]
    
    if @query.present?
      begin
        # 1. Embed the user's search query into a vector
        vector = OpenRouterClient.new.embed(@query)
        
        if vector.present?
          # nearest_neighbors must be called FIRST.
          # Use .preload (not .includes) — includes triggers a COUNT subquery that
          # conflicts with pgvector's AS neighbor_distance alias → SQL crash.
          # Materialize with .to_a so the view never fires extra COUNT queries on the relation.
          @results = Article.nearest_neighbors(:embedding, vector, distance: "cosine")
                            .preload(:country, :region, :ai_analysis)
                            .limit(20)
                            .to_a
        else
          @results = []
          flash.now[:alert] = "Failed to generate semantic search vector."
        end
      rescue StandardError => e
        @results = []
        flash.now[:alert] = "Search Error: #{e.message}"
        Rails.logger.error "[SEMANTIC SEARCH] Error: #{e.message}"
      end
    else
      @results = []
    end
  end
end
