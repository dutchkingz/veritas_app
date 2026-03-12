class NarrativeConvergencesController < ApplicationController
  def index
    @convergences = NarrativeConvergence.active.recent.limit(30)
    @outliers     = NarrativeConvergenceService.new.top_outliers(limit: 8)
  end

  def show
    @convergence    = NarrativeConvergence.find(params[:id])
    @articles       = @convergence.articles.order(published_at: :desc)
    @origin_article = Article.find_by(id: @convergence.origin_article_id)
  end

  def run_detection
    DetectNarrativeConvergencesJob.perform_later
    redirect_to narrative_convergences_path,
                notice: "Detection job queued. Results will appear within 60-90 seconds."
  end
end
