class CreateIntelligenceReports < ActiveRecord::Migration[8.1]
  def change
    create_table :intelligence_reports do |t|
      t.references :region, null: false, foreign_key: true
      t.text :summary
      t.jsonb :analyzed_article_ids, default: []
      t.string :status, default: "pending", null: false

      t.timestamps
    end

    add_index :intelligence_reports, :status
  end
end
