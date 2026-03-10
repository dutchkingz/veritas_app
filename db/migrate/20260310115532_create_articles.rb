class CreateArticles < ActiveRecord::Migration[8.1]
  def change
    create_table :articles do |t|
      t.string :headline
      t.string :source_url
      t.string :source_name
      t.datetime :published_at
      t.datetime :fetched_at
      t.float :latitude
      t.float :longitude
      t.references :country, null: false, foreign_key: true
      t.references :region, null: false, foreign_key: true
      t.integer :target_country
      t.jsonb :raw_data

      t.timestamps
    end
  end
end
