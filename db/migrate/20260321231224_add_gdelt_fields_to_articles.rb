class AddGdeltFieldsToArticles < ActiveRecord::Migration[8.1]
  def change
    add_column :articles, :data_source, :string, default: "newsapi", null: false
    add_column :articles, :original_language, :string
    add_index :articles, :data_source
  end
end
