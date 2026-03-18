class CreateSourceCredibilities < ActiveRecord::Migration[8.1]
  def change
    create_table :source_credibilities do |t|
      t.string   :source_name,            null: false
      t.integer  :articles_analyzed,      default: 0, null: false
      t.float    :rolling_trust_score,    default: 0.0, null: false
      t.float    :anomaly_rate,           default: 0.0
      t.integer  :high_threat_count,      default: 0
      t.integer  :low_threat_count,       default: 0
      t.jsonb    :topic_distribution,     default: {}
      t.jsonb    :sentiment_distribution, default: {}
      t.jsonb    :coordination_flags,     default: []
      t.float    :credibility_grade,      default: 50.0, null: false
      t.datetime :first_analyzed_at
      t.datetime :last_analyzed_at

      t.timestamps
    end

    add_index :source_credibilities, :source_name, unique: true
    add_index :source_credibilities, :credibility_grade
    add_index :source_credibilities, :rolling_trust_score
  end
end
