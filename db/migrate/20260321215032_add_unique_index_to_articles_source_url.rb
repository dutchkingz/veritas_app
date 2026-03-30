class AddUniqueIndexToArticlesSourceUrl < ActiveRecord::Migration[8.1]
  def up
    # Identify duplicate article ids to remove (keep lowest id per source_url).
    execute <<~SQL
      CREATE TEMP TABLE dup_article_ids AS
      SELECT id FROM articles
      WHERE source_url IS NOT NULL
        AND id NOT IN (
          SELECT MIN(id)
          FROM articles
          WHERE source_url IS NOT NULL
          GROUP BY source_url
        );
    SQL

    # Remove child records referencing duplicate articles before deleting the articles.
    # narrative_routes references narrative_arcs, so it must go first.
    execute <<~SQL
      DELETE FROM narrative_routes
      WHERE narrative_arc_id IN (
        SELECT id FROM narrative_arcs
        WHERE article_id IN (SELECT id FROM dup_article_ids)
      );
    SQL

    %w[
      ai_analyses
      entity_mentions
      narrative_arcs
      narrative_signature_articles
      saved_articles
    ].each do |table|
      execute "DELETE FROM #{table} WHERE article_id IN (SELECT id FROM dup_article_ids);"
    end

    execute <<~SQL
      DELETE FROM contradiction_logs
      WHERE article_a_id IN (SELECT id FROM dup_article_ids)
         OR article_b_id IN (SELECT id FROM dup_article_ids);
    SQL

    execute "DELETE FROM articles WHERE id IN (SELECT id FROM dup_article_ids);"
    execute "DROP TABLE dup_article_ids;"

    add_index :articles, :source_url,
              unique: true,
              where: "source_url IS NOT NULL",
              name: "index_articles_on_source_url_unique"
  end

  def down
    remove_index :articles, name: "index_articles_on_source_url_unique"
  end
end
