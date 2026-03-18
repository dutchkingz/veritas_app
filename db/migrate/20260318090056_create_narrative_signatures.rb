class CreateNarrativeSignatures < ActiveRecord::Migration[8.1]
  def change
    create_table :narrative_signatures do |t|
      t.string   :label,                null: false
      t.vector   :centroid,             limit: 1536
      t.integer  :match_count,          default: 0, null: false
      t.float    :avg_trust_score,      default: 0.0
      t.string   :dominant_threat_level
      t.jsonb    :source_distribution,  default: {}
      t.jsonb    :country_distribution, default: {}
      t.datetime :first_seen_at,        null: false
      t.datetime :last_seen_at,         null: false
      t.boolean  :active,               default: true, null: false

      t.timestamps
    end

    add_index :narrative_signatures, :active
    add_index :narrative_signatures, :last_seen_at
    add_index :narrative_signatures, :match_count

    create_table :narrative_signature_articles do |t|
      t.references :narrative_signature, null: false, foreign_key: true
      t.references :article,             null: false, foreign_key: true
      t.float      :cosine_distance
      t.datetime   :matched_at,          null: false
    end

    add_index :narrative_signature_articles,
              [:narrative_signature_id, :article_id],
              unique: true,
              name: "idx_sig_articles_unique"
  end
end
