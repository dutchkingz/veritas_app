class CreateTelegramChannels < ActiveRecord::Migration[8.1]
  def change
    create_table :telegram_channels do |t|
      t.string :channel_id, null: false
      t.string :title
      t.string :username
      t.integer :member_count
      t.string :topic
      t.boolean :monitoring_active, default: true

      t.timestamps
    end
    add_index :telegram_channels, :channel_id, unique: true

    # Changes related to the 'articles' table, as per the instruction and code edit
    add_column :articles, :source_type, :string, default: "news_api"
    add_column :articles, :telegram_channel_id, :string
    add_column :articles, :telegram_message_id, :string
    add_column :articles, :telegram_views, :integer
    add_column :articles, :telegram_forwards, :integer

    add_index :articles, :source_type
    add_index :articles, [:telegram_channel_id, :telegram_message_id], name: "index_articles_on_telegram_metadata"
  end
end
