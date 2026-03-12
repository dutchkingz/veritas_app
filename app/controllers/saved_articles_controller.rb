class SavedArticlesController < ApplicationController
  before_action :authenticate_user!

  def index
    @saved_articles = current_user.saved_articles.order(created_at: :desc)
  end

  def show
    @saved_article = current_user.saved_articles.find(params[:id])
  end

  def create
    @article = Article.find(params[:article_id])
    
    @saved_article = current_user.saved_articles.build(
      article: @article,
      headline: @article.headline,
      content: @article.content,
      source_name: @article.source_name,
      published_at: @article.published_at
    )

    if @saved_article.save
      redirect_to article_path(@article), notice: "Article correctly saved. It will now be available in your Saved Articles page."
    else
      redirect_to article_path(@article), alert: "Unable to save article."
    end
  end

  def destroy
    @saved_article = current_user.saved_articles.find(params[:id])
    @saved_article.destroy
    redirect_to saved_articles_path, notice: "Saved article removed."
  end
end
