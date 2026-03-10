class Article < ApplicationRecord
  belongs_to :country
  belongs_to :region
end
