class SavedArticle < ApplicationRecord
  belongs_to :user
  belongs_to :article, optional: true

  validates :headline, presence: true
  validates :content, presence: true
  validates :article_id, uniqueness: { scope: :user_id }, allow_nil: true
end
