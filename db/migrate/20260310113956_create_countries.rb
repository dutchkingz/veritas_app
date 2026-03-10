class CreateCountries < ActiveRecord::Migration[8.1]
  def change
    create_table :countries do |t|
      t.references :region, null: false, foreign_key: true
      t.string :name
      t.string :iso_code

      t.timestamps
    end
  end
end
