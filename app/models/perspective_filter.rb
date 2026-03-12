class PerspectiveFilter < ApplicationRecord
  # keywords — comma-separated source name patterns (case-insensitive matching)
  # filter_type — "source" (matches article.source_name)

  def keywords_list
    keywords.to_s.split(',').map(&:strip).reject(&:blank?)
  end

  def color
    case name.downcase
    when /liberal/     then '#38bdf8'
    when /conservative/ then '#ef4444'
    when /china/       then '#f97316'
    when /russia/      then '#dc2626'
    when /mainstream/  then '#22c55e'
    when /global south/ then '#eab308'
    else '#64748b'
    end
  end

  def matches_source?(source_name)
    return false if source_name.blank?
    keywords_list.any? { |kw| source_name.downcase.include?(kw.strip.downcase) }
  end
end
