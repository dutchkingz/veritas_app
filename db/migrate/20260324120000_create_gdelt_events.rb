class CreateGdeltEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :gdelt_events do |t|
      # GDELT primary identifier — monotonically increasing integer.
      # Used as high-water mark to avoid re-fetching already-ingested events.
      t.bigint  :globaleventid, null: false

      # Date in YYYYMMDD integer format (GDELT native) + parsed date for queries
      t.integer :sqldate
      t.date    :event_date

      # Actor 1 — the initiating actor
      t.string  :actor1_name
      t.string  :actor1_country_code   # FIPS 10-4
      t.string  :actor1_type1_code     # CAMEO actor type (e.g. GOV, MIL, OPP)

      # Actor 2 — the target actor
      t.string  :actor2_name
      t.string  :actor2_country_code
      t.string  :actor2_type1_code

      # CAMEO event classification
      t.string  :event_code            # Full CAMEO code (e.g. "190", "1411")
      t.string  :event_root_code       # Root CAMEO code (e.g. "19", "14")
      t.integer :quad_class            # 1=Verbal Coop, 2=Material Coop, 3=Verbal Conflict, 4=Material Conflict

      # Conflict intensity metrics
      t.float   :goldstein_scale       # -10.0 (most destabilizing) to +10.0 (most stabilizing)
      t.float   :avg_tone              # Average tone of source articles (-100 to +100)

      # Source volume — higher = more credible / widely reported
      t.integer :num_mentions
      t.integer :num_sources
      t.integer :num_articles

      # Primary geo: where the action took place
      t.float   :action_geo_lat
      t.float   :action_geo_long
      t.string  :action_geo_country_code
      t.string  :action_geo_full_name

      # Source URL from GDELT — used to match against articles.source_url
      t.text    :source_url
      # Normalized form (no scheme, no tracking params, lowercased) for efficient matching
      t.string  :source_url_normalized

      # Nullable FK to articles — set when source_url matches an ingested article
      t.bigint  :article_id

      # Catch-all for additional GDELT fields added in future phases
      t.jsonb   :raw_data, default: {}

      t.timestamps
    end

    add_index :gdelt_events, :globaleventid, unique: true
    add_index :gdelt_events, :event_date
    add_index :gdelt_events, :quad_class
    add_index :gdelt_events, :goldstein_scale
    add_index :gdelt_events, :article_id
    add_index :gdelt_events, :source_url_normalized
    add_index :gdelt_events, :action_geo_country_code
  end
end
