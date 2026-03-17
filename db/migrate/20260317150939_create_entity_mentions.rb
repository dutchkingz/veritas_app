class CreateEntityMentions < ActiveRecord::Migration[8.1]
  def change
    create_table :entity_mentions do |t|
      t.references :entity,  null: false, foreign_key: true
      t.references :article, null: false, foreign_key: true

      t.timestamps
    end

    add_index :entity_mentions, [:entity_id, :article_id], unique: true
  end
end
