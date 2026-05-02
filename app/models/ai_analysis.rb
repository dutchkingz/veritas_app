class AiAnalysis < ApplicationRecord
  include ConfidenceScoreable

  belongs_to :article

  after_update_commit :broadcast_color_update, if: :analysis_complete?

  # Normalize threat_level to a canonical label.
  # threat_level can be stored as a string ("CRITICAL") or legacy integer (1-10).
  # All three methods use normalized_threat_level to avoid the .to_i bug where
  # a string like "HIGH".to_i silently returns 0 → NEGLIGIBLE.
  THREAT_LABELS = %w[CRITICAL HIGH MODERATE LOW NEGLIGIBLE].freeze

  THREAT_LABEL_COLORS = {
    "CRITICAL"   => "#ff3a5e",
    "HIGH"       => "#ff6b2b",
    "MODERATE"   => "#ffc107",
    "LOW"        => "#22c55e",
    "NEGLIGIBLE" => "#6b7280"
  }.freeze

  THREAT_LABEL_SCORES = {
    "CRITICAL"   => 9,
    "HIGH"       => 7,
    "MODERATE"   => 4,
    "LOW"        => 2,
    "NEGLIGIBLE" => 1
  }.freeze

  def threat_label
    normalized_threat_level
  end

  def threat_color
    THREAT_LABEL_COLORS[normalized_threat_level] || "#6b7280"
  end

  # Returns a numeric threat score (1-10).
  def threat_numeric
    THREAT_LABEL_SCORES[normalized_threat_level] || 1
  end

  private

  # Single source of truth: converts any stored threat_level to a canonical label.
  # Handles: string labels, legacy integers, stringified integers, nil, and garbage.
  def normalized_threat_level
    raw = threat_level.to_s.strip.upcase
    return raw if THREAT_LABELS.include?(raw)

    # Only parse as integer if the string is actually numeric
    if raw.match?(/\A\d+\z/)
      case raw.to_i
      when 8..10 then "CRITICAL"
      when 5..7  then "HIGH"
      when 3..4  then "MODERATE"
      when 2     then "LOW"
      else "NEGLIGIBLE"
      end
    else
      # Unknown string that isn't a label or number — don't silently map to NEGLIGIBLE
      Rails.logger.warn "[AiAnalysis] Unknown threat_level '#{threat_level}' for article ##{article_id}" if threat_level.present?
      "NEGLIGIBLE"
    end
  end

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
