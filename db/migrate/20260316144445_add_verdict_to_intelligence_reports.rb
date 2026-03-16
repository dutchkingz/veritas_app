class AddVerdictToIntelligenceReports < ActiveRecord::Migration[8.1]
  def change
    add_column :intelligence_reports, :verdict, :string
  end
end
