class Article < ApplicationRecord
  has_neighbors :embedding

  belongs_to :country, optional: true
  belongs_to :region, optional: true
  has_one :ai_analysis, dependent: :destroy
  has_many :narrative_arcs, dependent: :destroy
end
