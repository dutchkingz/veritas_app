class Article < ApplicationRecord
  has_neighbors :embedding

  belongs_to :country, optional: true
  belongs_to :region, optional: true
  has_one :ai_analysis, dependent: :destroy
  has_many :narrative_arcs, dependent: :destroy

  # ----------------------------------------------------------
  # Scopes for Regional Intelligence Analysis
  # ----------------------------------------------------------

  # Articles published within the last 48 hours
  scope :recent_48h, -> { where("published_at >= ?", 48.hours.ago) }

  # Filter by region name (case-insensitive) via JOIN
  scope :by_region_name, ->(name) {
    joins(:region).where("LOWER(regions.name) = LOWER(?)", name)
  }
end
