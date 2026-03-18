class PerspectiveFilter < ApplicationRecord
  # keywords — comma-separated source name patterns (case-insensitive matching)
  # filter_type — "source" (matches article.source_name)

  def keywords_list
    keywords.to_s.split(',').map(&:strip).reject(&:blank?)
  end

  # Stable slug — used as the canonical identifier throughout JS/CSS/services.
  # Independent of database ID so it survives re-seeds and migrations.
  def slug
    case name.downcase
    when /liberal/      then "us_liberal"
    when /conservative/ then "us_conservative"
    when /china/        then "china_state"
    when /russia/       then "russia_state"
    when /mainstream/   then "western_mainstream"
    when /global south/ then "global_south"
    else name.downcase.gsub(/\s+/, "_")
    end
  end

  def color
    case slug
    when "western_mainstream" then "#38bdf8"
    when "us_liberal"         then "#60a5fa"
    when "us_conservative"    then "#f87171"
    when "china_state"        then "#f97316"
    when "russia_state"       then "#dc2626"
    when "global_south"       then "#eab308"
    else "#64748b"
    end
  end

  # Flag emoji for the compass UI
  def flag
    case slug
    when "western_mainstream" then "🌐"
    when "us_liberal"         then "🔵"
    when "us_conservative"    then "🔴"
    when "china_state"        then "🇨🇳"
    when "russia_state"       then "🇷🇺"
    when "global_south"       then "🌍"
    else "◈"
    end
  end

  # Short label for compact display
  def short_label
    case slug
    when "western_mainstream" then "NEUTRAL"
    when "us_liberal"         then "US-LEFT"
    when "us_conservative"    then "US-RIGHT"
    when "china_state"        then "CHINA"
    when "russia_state"       then "RUSSIA"
    when "global_south"       then "SOUTH"
    else name.upcase.truncate(8, omission: "")
    end
  end

  def matches_source?(source_name)
    return false if source_name.blank?
    keywords_list.any? { |kw| source_name.downcase.include?(kw.strip.downcase) }
  end
end
