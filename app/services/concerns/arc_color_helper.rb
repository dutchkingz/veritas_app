module ArcColorHelper
  extend ActiveSupport::Concern

  DEFAULT_ARC_COLOR = "#00f0ff".freeze

  private

  def arc_start_color_for(article, perspective)
    semantic_color_for(article) || perspective&.color || threat_color_for(article.region&.threat_level) || DEFAULT_ARC_COLOR
  end

  def arc_end_color_for(origin_article, target_article, perspective)
    end_color = semantic_color_for(target_article) ||
                semantic_color_for(origin_article) ||
                perspective&.color ||
                threat_color_for(target_article.region&.threat_level) ||
                threat_color_for(origin_article.region&.threat_level) ||
                DEFAULT_ARC_COLOR

    brighten_hex(end_color, 0.18)
  end

  def semantic_color_for(article)
    analysis = article.ai_analysis
    return analysis.sentiment_color if analysis&.sentiment_color.present?

    threat_color_for(analysis&.threat_level || article.region&.threat_level)
  end

  def threat_color_for(threat)
    case threat.to_s.upcase
    when "3", "CRITICAL" then "#ef4444"
    when "2", "HIGH", "MODERATE" then "#f59e0b"
    when "1", "LOW" then "#22c55e"
    when "0", "NEGLIGIBLE" then "#38bdf8"
    else
      nil
    end
  end

  def brighten_hex(hex_color, factor)
    hex = hex_color.to_s.delete_prefix("#")
    return DEFAULT_ARC_COLOR unless hex.match?(/\A[\da-fA-F]{6}\z/)

    channels = hex.scan(/../).map { |pair| pair.to_i(16) }
    brightened = channels.map do |channel|
      (channel + ((255 - channel) * factor)).round.clamp(0, 255)
    end

    "##{brightened.map { |value| value.to_s(16).rjust(2, "0") }.join}"
  end
end
