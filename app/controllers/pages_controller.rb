class PagesController < ApplicationController
  def home
    @articles = Article.includes(:country, :region).order(published_at: :desc).limit(50)
  end
end
