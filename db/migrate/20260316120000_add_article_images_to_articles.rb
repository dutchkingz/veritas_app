class AddArticleImagesToArticles < ActiveRecord::Migration[8.0]
  def change
    add_column :articles, :article_images, :jsonb, default: [], null: false
  end
end
