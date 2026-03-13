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

    @saved_article = current_user.saved_articles.find_or_initialize_by(article: @article)
    @saved_article.assign_attributes(
      headline: @article.headline,
      content: @article.content,
      source_name: @article.source_name,
      published_at: @article.published_at
    )

    if @saved_article.save
      message = @saved_article.previously_new_record? ? "Article correctly saved. It will now be available in your Saved Articles page." : "Article already exists in your saved intelligence."
      redirect_to article_path(@article), notice: message
    else
      redirect_to article_path(@article), alert: "Unable to save article."
    end
  end

  def destroy
    @saved_article = current_user.saved_articles.find(params[:id])
    @saved_article.destroy
    redirect_to saved_articles_path, notice: "Saved article removed."
  end

  def watchlist
    saved = current_user.saved_articles.includes(:article).to_a
    signature_articles = saved.map(&:article).compact.select { |a| a.embedding.present? }

    if signature_articles.empty?
      @watchlist_hits = []
      return
    end

    saved_ids = saved.map(&:article_id).compact.to_set
    raw_hits  = []

    signature_articles.each do |sig|
      Article
        .joins(:ai_analysis)
        .where.not(id: saved_ids.to_a)
        .where(published_at: 7.days.ago..Time.current)
        .where(ai_analyses: { analysis_status: 'complete' })
        .nearest_neighbors(:embedding, sig.embedding, distance: "cosine")
        .preload(:ai_analysis, :country)
        .limit(8)
        .each do |hit|
          next unless hit.neighbor_distance < 0.25
          raw_hits << {
            article:    hit,
            signature:  sig,
            similarity: ((1.0 - hit.neighbor_distance) * 100).round(1)
          }
        end
    end

    # Deduplicate: if the same article matches multiple signatures, keep the closest
    @watchlist_hits = raw_hits
      .group_by { |h| h[:article].id }
      .map       { |_, hits| hits.max_by { |h| h[:similarity] } }
      .sort_by   { |h| -h[:similarity] }
      .first(20)
  end
end
