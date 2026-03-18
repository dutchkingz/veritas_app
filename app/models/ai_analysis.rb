class AiAnalysis < ApplicationRecord
  include ConfidenceScoreable

  belongs_to :article

  after_update_commit :broadcast_color_update, if: :analysis_complete?

  # Threat color mapping for visualization
  def threat_color
    case threat_level.to_i
    when 8..10 then "#ff4444"  # Critical red
    when 5..7  then "#ff9900"  # High orange
    when 3..4  then "#ffcc00"  # Medium yellow
    else "#22c55e"              # Low green
    end
  end

  private

  def analysis_complete?
    analysis_status == "complete" && saved_change_to_analysis_status?
  end

  def broadcast_color_update
    ActionCable.server.broadcast("globe", {
      type: "update_point",
      point: {
        id:    article_id,
        color: sentiment_color || "#00f0ff"
      }
    })
  rescue StandardError => e
    Rails.logger.warn "[VERITAS Globe] Broadcast skipped for Article ##{article_id}: #{e.class} #{e.message}"
  end
end
