class CreateUserModelConfigs < ActiveRecord::Migration[8.1]
  def change
    create_table :user_model_configs do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }

      t.string :analyst_model,  default: "google/gemini-2.0-flash-001", null: false
      t.string :sentinel_model, default: "openai/gpt-4o-mini",          null: false
      t.string :arbiter_model,  default: "anthropic/claude-3.5-haiku",  null: false
      t.string :briefing_model, default: "anthropic/claude-3.5-haiku",  null: false
      t.string :voice_model,    default: "anthropic/claude-3.5-haiku",  null: false

      t.string  :custom_endpoint_url
      t.string  :custom_api_key_encrypted
      t.boolean :use_custom_endpoint, default: false, null: false

      t.timestamps
    end
  end
end
