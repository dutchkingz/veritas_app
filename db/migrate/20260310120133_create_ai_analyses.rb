class CreateAiAnalyses < ActiveRecord::Migration[8.1]
  def change
    create_table :ai_analyses do |t|
      t.references :article, null: false, foreign_key: true
      t.float :trust_score
      t.string :sentiment_label
      t.string :sentiment_color
      t.string :summary
      t.string :geopolitical_topic
      t.string :threat_level
      t.boolean :linguistic_anomaly_flag
      t.string :anomaly_notes

      t.timestamps
    end
  end
end
