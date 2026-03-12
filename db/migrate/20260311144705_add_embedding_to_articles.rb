class AddEmbeddingToArticles < ActiveRecord::Migration[8.1]
  def change
    add_column :articles, :embedding, :vector, limit: 1536 # OpenAI text-embedding-3-small dimension
  end
end
