class CreateIntelligenceBriefs < ActiveRecord::Migration[8.1]
  def change
    create_table :intelligence_briefs do |t|
      t.string   :brief_type,          null: false
      t.string   :title,               null: false
      t.text     :executive_summary
      t.jsonb    :narrative_trends,     default: []
      t.jsonb    :source_alerts,        default: []
      t.jsonb    :contradictions,       default: []
      t.jsonb    :blind_spots,          default: []
      t.jsonb    :confidence_map,       default: {}
      t.integer  :articles_processed,   default: 0
      t.integer  :signatures_active,    default: 0
      t.integer  :contradictions_found, default: 0
      t.string   :status,              default: "generating", null: false
      t.datetime :period_start
      t.datetime :period_end

      t.timestamps
    end

    add_index :intelligence_briefs, :brief_type
    add_index :intelligence_briefs, :created_at
    add_index :intelligence_briefs, :status
  end
end
