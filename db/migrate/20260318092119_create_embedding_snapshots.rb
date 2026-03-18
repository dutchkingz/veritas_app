class CreateEmbeddingSnapshots < ActiveRecord::Migration[8.1]
  def change
    create_table :embedding_snapshots do |t|
      t.datetime :captured_at,     null: false
      t.integer  :article_count,   null: false
      t.integer  :cluster_count,   default: 0
      t.jsonb    :cluster_summary, default: []
      t.jsonb    :drift_metrics,   default: {}
      t.jsonb    :outlier_ids,     default: []

      t.timestamps
    end

    add_index :embedding_snapshots, :captured_at
  end
end
