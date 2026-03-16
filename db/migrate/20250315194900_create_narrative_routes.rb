class CreateNarrativeRoutes < ActiveRecord::Migration[8.1]
  def change
    create_table :narrative_routes do |t|
      # Foreign key to existing NarrativeArc (one arc can have multiple routes)
      t.references :narrative_arc, null: false, foreign_key: true
      
      # Core route metadata
      t.string :name
      t.text :description
      
      # Hops as JSONB array - the heart of ARCWEAVER 2.0
      # Structure matches your vision:
      # [
      #   {
      #     "source_name": "RT",
      #     "source_country": "Russia",
      #     "lat": 55.75,
      #     "lng": 37.61,
      #     "published_at": "2024-01-15T06:00:00Z",
      #     "delay_from_previous": 0,  # minutes since previous hop
      #     "framing_shift": "original", # original/amplified/distorted/neutralized
      #     "article_id": 123,          # optional reference to Article
      #     "confidence_score": 0.95    # 0-1 how confident we are about this hop
      #   },
      #   ...
      # ]
      t.jsonb :hops, default: [], null: false
      
      # Analytics derived from hops
      t.integer :total_hops, default: 0
      t.integer :total_reach_countries, default: 0
      t.float :propagation_speed # km/h or hops/hour
      t.float :manipulation_score, default: 0.0 # 0-1 how distorted the narrative became
      t.float :amplification_score, default: 0.0 # 0-1 how much amplification occurred
      
      # Timeline metadata for fast queries
      t.jsonb :timeline, default: [] # array of [timestamp, lat, lng, source_name]
      t.datetime :first_hop_at
      t.datetime :last_hop_at
      t.integer :total_duration_seconds, default: 0 # last_hop_at - first_hop_at
      
      # Route status
      t.boolean :is_complete, default: false
      t.string :status, default: "tracking" # tracking/complete/stale
      
      # For backward compatibility with existing globe_controller.js
      t.string :origin_country
      t.float :origin_lat
      t.float :origin_lng
      t.string :target_country
      t.float :target_lat
      t.float :target_lng
      t.string :arc_color
      
      # Performance optimizations
      t.index :first_hop_at
      t.index :last_hop_at
      t.index :is_complete
      t.index :manipulation_score
      t.index [:origin_country, :target_country]
      
      t.timestamps
    end
  end
end