class CreateNarrativeArcs < ActiveRecord::Migration[8.1]
  def change
    create_table :narrative_arcs do |t|
      t.references :article, null: false, foreign_key: true
      t.string :origin_country
      t.float :origin_lat
      t.float :origin_lng
      t.string :target_country
      t.float :target_lat
      t.float :target_lng
      t.string :arc_color

      t.timestamps
    end
  end
end
