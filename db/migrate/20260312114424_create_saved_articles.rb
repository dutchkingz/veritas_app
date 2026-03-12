class CreateSavedArticles < ActiveRecord::Migration[8.1]
  def change
    create_table :saved_articles do |t|
      t.references :user, null: false, foreign_key: true
      t.references :article, null: false, foreign_key: true
      t.string :headline
      t.string :source_name
      t.datetime :published_at
      t.text :content

      t.timestamps
    end
  end
end
