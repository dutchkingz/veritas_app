class AddTrustScoreVarianceToSourceCredibilities < ActiveRecord::Migration[8.1]
  def change
    add_column :source_credibilities, :trust_score_variance, :float, default: 0.0, null: false
  end
end
