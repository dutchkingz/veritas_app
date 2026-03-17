class CreateEntities < ActiveRecord::Migration[8.1]
  def change
    create_table :entities do |t|
      t.string  :name,             null: false
      t.string  :entity_type,      null: false
      t.string  :normalized_name,  null: false
      t.datetime :first_seen_at
      t.integer :mentions_count,   default: 0, null: false

      t.timestamps
    end

    add_index :entities, [:normalized_name, :entity_type], unique: true
    add_index :entities, :entity_type
    add_index :entities, :mentions_count
  end
end
