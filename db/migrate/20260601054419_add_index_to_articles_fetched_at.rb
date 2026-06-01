class AddIndexToArticlesFetchedAt < ActiveRecord::Migration[8.1]
  def change
    add_index :articles, :fetched_at
    add_index :ai_analyses, :analysis_status
  end
end
