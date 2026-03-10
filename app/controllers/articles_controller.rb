class ArticlesController < ApplicationController
  def show
    @article = Article.includes(:country, :region, :ai_analysis, :narrative_arcs).find(params[:id])
  end
end
