class Article < ApplicationRecord
  DEMO_SOURCE_HOST = "demo.veritas.local".freeze

  has_neighbors :embedding

  belongs_to :country, optional: true
  belongs_to :region, optional: true
  has_one :ai_analysis, dependent: :destroy
  has_many :narrative_arcs, dependent: :destroy
  has_many :saved_articles, dependent: :destroy
  has_many :entity_mentions, dependent: :destroy
  has_many :entities, through: :entity_mentions

  after_create_commit :broadcast_sidebar_update
  after_create_commit :broadcast_to_globe
  after_create_commit :enqueue_content_fetch

  # ----------------------------------------------------------
  # Scopes for Regional Intelligence Analysis
  # ----------------------------------------------------------

  # Articles published within the last 48 hours
  scope :recent_48h, -> { where("published_at >= ?", 48.hours.ago) }

  # Filter by region name (case-insensitive) via JOIN
  scope :by_region_name, ->(name) {
    joins(:region).where("LOWER(regions.name) = LOWER(?)", name)
  }

  def fallback_demo?
    raw_data.is_a?(Hash) && raw_data["seed_mode"] == "fallback_demo"
  end

  def fetchable_source?
    return false if source_url.blank? || fallback_demo?

    true
  end

  def best_narrative_route
    routes = narrative_arcs.flat_map(&:narrative_routes).select { |route| route.hops.present? }
    routes.max_by do |route|
      [
        route.is_complete? ? 1 : 0,
        route.total_hops.to_i,
        route.manipulation_score.to_f,
        route.created_at.to_i
      ]
    end
  end

  def best_journey_data
    best_narrative_route&.as_journey_data
  end

  private

  def enqueue_content_fetch
    return unless fetchable_source?
    FetchArticleContentJob.perform_later(id)
  end

  def broadcast_sidebar_update
    # Don't push GDELT articles with placeholder headlines to the sidebar
    return if headline.to_s.end_with?("— GDELT")

    broadcast_prepend_to(
      "hot_articles",
      target: "hot-articles-feed",
      partial: "articles/sidebar_item",
      locals: { article: self, is_new: true }
    )
  end

  def broadcast_to_globe
    ActionCable.server.broadcast("globe", {
      type: "new_point",
      point: {
        id:       id,
        lat:      latitude,
        lng:      longitude,
        size:     0.4,
        color:    ai_analysis&.sentiment_color || "#00f0ff",
        headline: headline,
        source:   source_name
      }
    })
  end
end
