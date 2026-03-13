class AiAnalysis < ApplicationRecord
  belongs_to :article

  after_update_commit :broadcast_color_update, if: :analysis_complete?

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
