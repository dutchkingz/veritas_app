class CreateRegions < ActiveRecord::Migration[8.1]
  def change
    create_table :regions do |t|
      t.string :name
      t.float :latitude
      t.float :longitude
      t.integer :threat_level
      t.integer :article_volume
      t.datetime :last_calculated_at

      t.timestamps
    end
  end
end
