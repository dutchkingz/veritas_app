class SavedArticle < ApplicationRecord
  belongs_to :user
  belongs_to :article, optional: true

  validates :headline, presence: true
  validates :content, presence: true
end
