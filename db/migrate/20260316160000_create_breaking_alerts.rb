class CreateBreakingAlerts < ActiveRecord::Migration[8.0]
  def change
    create_table :breaking_alerts do |t|
      t.string  :headline,     null: false
      t.text    :briefing,     null: false
      t.integer :severity,     null: false, default: 0
      t.float   :lat,          null: false
      t.float   :lng,          null: false
      t.references :region,    foreign_key: true, null: true
      t.references :triggered_by, foreign_key: { to_table: :users }, null: true
      t.string  :source_type,  null: false, default: "auto"
      t.jsonb   :metadata,     null: false, default: {}
      t.datetime :expires_at
      t.integer :status,       null: false, default: 0

      t.timestamps
    end

    add_index :breaking_alerts, :status
    add_index :breaking_alerts, :created_at
  end
end
