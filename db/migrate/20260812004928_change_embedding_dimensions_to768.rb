class ChangeEmbeddingDimensionsTo768 < ActiveRecord::Migration[8.1]
  def up
    # Clear existing 1536-dim embeddings — they're incompatible with Google's 768-dim model.
    # They'll be regenerated via GenerateEmbeddingJob.
    execute "UPDATE articles SET embedding = NULL WHERE embedding IS NOT NULL"
    execute "UPDATE narrative_signatures SET centroid = NULL WHERE centroid IS NOT NULL"

    # Resize vector columns from 1536 to 768
    change_column :articles, :embedding, :vector, limit: 768
    change_column :narrative_signatures, :centroid, :vector, limit: 768
  end

  def down
    change_column :articles, :embedding, :vector, limit: 1536
    change_column :narrative_signatures, :centroid, :vector, limit: 1536
  end
end
