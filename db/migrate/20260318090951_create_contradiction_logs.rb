class CreateContradictionLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :contradiction_logs do |t|
      t.references :article_a, null: false, foreign_key: { to_table: :articles }
      t.references :article_b, null: false, foreign_key: { to_table: :articles }
      t.string     :contradiction_type, null: false
      t.text       :description
      t.float      :severity,            default: 0.0
      t.float      :embedding_similarity
      t.string     :source_a
      t.string     :source_b
      t.jsonb      :metadata,            default: {}

      t.timestamps
    end

    add_index :contradiction_logs, :contradiction_type
    add_index :contradiction_logs, :severity
    add_index :contradiction_logs, [:article_a_id, :article_b_id], unique: true, name: "idx_contradiction_pair"
  end
end
