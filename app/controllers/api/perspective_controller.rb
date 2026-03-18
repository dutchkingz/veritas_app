module Api
  class PerspectiveController < ApplicationController
    skip_before_action :authenticate_user!, only: [:context]

    # GET /api/perspective/:slug/context?topic=NATO
    #
    # Returns narrative context for a perspective lens:
    #   - active source list
    #   - divergence score vs Western Mainstream baseline
    #   - top narrative frames (from existing ai_analysis summaries)
    def context
      slug  = params[:slug]
      topic = params[:topic].presence

      unless SourceClassifierService::PERSPECTIVE_SLUGS.include?(slug)
        return render json: { error: "Unknown perspective: #{slug}" }, status: :bad_request
      end

      # Divergence score
      divergence = NarrativeDivergenceService.new(slug, topic: topic).compute

      # Top narrative frames — top 6 summaries from matching articles
      frames = fetch_narrative_frames(slug, topic)

      # Source list for this lens
      sources = SourceClassifierService.sources_for(slug).first(12).map(&:titleize)

      render json: {
        slug:       slug,
        label:      SourceClassifierService.display_name(slug),
        divergence: divergence,
        frames:     frames,
        sources:    sources,
        topic:      topic
      }
    end

    private

    def fetch_narrative_frames(slug, topic)
      source_names = SourceClassifierService.sources_for(slug)
      return [] if source_names.empty?

      conditions = source_names.map { "LOWER(articles.source_name) LIKE ?" }.join(" OR ")
      values     = source_names.map { |s| "%#{s}%" }

      scope = Article
        .joins(:ai_analysis)
        .where(conditions, *values)
        .where.not(ai_analyses: { analysis_status: "pending" })
        .where.not(ai_analyses: { summary: [nil, ""] })
        .order("articles.published_at DESC")

      scope = scope.where("articles.headline ILIKE ?", "%#{topic}%") if topic.present?

      scope.limit(6).pluck(
        "articles.headline",
        "articles.source_name",
        "ai_analyses.summary",
        "ai_analyses.sentiment_label",
        "ai_analyses.trust_score"
      ).map do |headline, source, summary, sentiment, trust|
        {
          headline:  headline,
          source:    source,
          summary:   summary&.truncate(200),
          sentiment: sentiment,
          trust:     trust&.round
        }
      end
    end
  end
end
