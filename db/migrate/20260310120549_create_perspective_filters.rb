class CreatePerspectiveFilters < ActiveRecord::Migration[8.1]
  def change
    create_table :perspective_filters do |t|
      t.string :name
      t.string :filter_type
      t.string :keywords

      t.timestamps
    end
  end
end
