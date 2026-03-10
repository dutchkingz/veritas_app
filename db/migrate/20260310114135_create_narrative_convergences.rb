class CreateNarrativeConvergences < ActiveRecord::Migration[8.1]
  def change
    create_table :narrative_convergences do |t|
      t.string :topic_keyword
      t.float :convergence_percentage
      t.integer :article_count
      t.datetime :calculated_at

      t.timestamps
    end
  end
end
