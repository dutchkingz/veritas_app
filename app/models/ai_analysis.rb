class AiAnalysis < ApplicationRecord
  include ConfidenceScoreable

  belongs_to :article

  after_update_commit :broadcast_color_update, if: :analysis_complete?

  # Normalize threat_level to a human-readable label.
  # Handles both string values (CRITICAL/HIGH/...) and legacy numeric (1-10).
  def threat_label
    case threat_level.to_s.upcase
    when "CRITICAL", "HIGH", "MODERATE", "LOW", "NEGLIGIBLE"
      threat_level.upcase
    else
      case threat_level.to_i
      when 8..10 then "CRITICAL"
      when 5..7  then "HIGH"
      when 3..4  then "MODERATE"
      when 2     then "LOW"
      else "NEGLIGIBLE"
      end
    end
  end

  # Threat color mapping for visualization.
  # threat_level can be a string (CRITICAL/HIGH/MODERATE/LOW/NEGLIGIBLE)
  # or a legacy numeric value (1-10).
  def threat_color
    case threat_level.to_s.upcase
    when "CRITICAL"          then "#ff3a5e"
    when "HIGH"              then "#ff6b2b"
    when "MODERATE"          then "#ffc107"
    when "LOW"               then "#22c55e"
    when "NEGLIGIBLE"        then "#6b7280"
    else
      # Legacy numeric values
      case threat_level.to_i
      when 8..10 then "#ff3a5e"
      when 5..7  then "#ff6b2b"
      when 3..4  then "#ffc107"
      when 2     then "#22c55e"
      else "#6b7280"
      end
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
