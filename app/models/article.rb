class Article < ApplicationRecord
  belongs_to :country
  belongs_to :region
  has_one :ai_analysis, dependent: :destroy
  has_many :narrative_arcs, dependent: :destroy
end
