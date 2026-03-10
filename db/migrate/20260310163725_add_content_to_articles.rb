class AddContentToArticles < ActiveRecord::Migration[8.1]
  def change
    add_column :articles, :content, :text
  end
end
