class Briefing < ApplicationRecord
  belongs_to :user

  # threat_summary — full LLM-generated briefing text (markdown sections)
  # top_narratives — JSON array of { label, threat, article_count } used as context

  def top_narratives_list
    JSON.parse(top_narratives)
  rescue JSON::ParserError, TypeError
    []
  end

  # Parse "## SECTION TITLE\n content..." into { "SECTION TITLE" => "content" }
  def sections
    return {} unless threat_summary.present?
    result = {}
    current = nil
    threat_summary.lines.each do |line|
      if (m = line.match(/^##\s+(.+)/))
        current = m[1].strip
        result[current] = +''
      elsif current
        result[current] << line
      end
    end
    result.transform_values(&:strip)
  end

  def age_label
    return 'Unknown' unless generated_at
    mins = ((Time.current - generated_at) / 60).round
    mins < 60 ? "#{mins}m ago" : "#{(mins / 60.0).round(1)}h ago"
  end
end
