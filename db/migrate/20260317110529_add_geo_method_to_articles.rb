class AddGeoMethodToArticles < ActiveRecord::Migration[8.1]
  def change
    add_column :articles, :geo_method, :string, default: "unresolved"
    change_column_null :articles, :region_id, true
    change_column_null :articles, :country_id, true
  end
end
