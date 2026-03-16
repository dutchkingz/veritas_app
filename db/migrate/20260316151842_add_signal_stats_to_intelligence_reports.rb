class AddSignalStatsToIntelligenceReports < ActiveRecord::Migration[8.1]
  def change
    add_column :intelligence_reports, :signal_stats, :jsonb
  end
end
