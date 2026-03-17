class EntityMention < ApplicationRecord
  belongs_to :entity,  counter_cache: :mentions_count
  belongs_to :article

  validates :entity_id, uniqueness: { scope: :article_id }
end
