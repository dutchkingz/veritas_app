class CreateBriefings < ActiveRecord::Migration[8.1]
  def change
    create_table :briefings do |t|
      t.references :user, null: false, foreign_key: true
      t.datetime :generated_at
      t.string :threat_summary
      t.string :top_narratives
      t.string :pdf_url

      t.timestamps
    end
  end
end
