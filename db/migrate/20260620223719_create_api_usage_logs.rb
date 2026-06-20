class CreateApiUsageLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :api_usage_logs do |t|
      t.string  :model,          null: false
      t.string  :agent_role,     null: false
      t.integer :input_tokens
      t.integer :output_tokens
      t.decimal :estimated_cost, precision: 10, scale: 6
      t.string  :status,         null: false
      t.string  :error_message
      t.integer :http_status
      t.timestamps
    end

    add_index :api_usage_logs, :created_at
    add_index :api_usage_logs, :status
    add_index :api_usage_logs, [:agent_role, :created_at]
  end
end
