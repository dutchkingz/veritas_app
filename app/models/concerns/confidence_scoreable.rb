module ConfidenceScoreable
  extend ActiveSupport::Concern

  def confidence_assessment(topic: nil, region: nil, source: nil)
    factors = {}

    if topic.present?
      count = AiAnalysis.where(geopolitical_topic: topic, analysis_status: "complete").count
      factors[:topic_depth] = { count: count, level: confidence_level(count) }
    end

    if region.present?
      count = Article.where(region: region, published_at: 30.days.ago..).count
      sources = Article.where(region: region, published_at: 30.days.ago..).distinct.count(:source_name)
      factors[:region_coverage] = { articles: count, sources: sources, level: confidence_level(count) }
    end

    if source.present?
      cred = SourceCredibility.find_by(source_name: source)
      factors[:source_credibility] = cred ? { grade: cred.credibility_grade, label: cred.grade_label } : { grade: 0, label: "UNKNOWN" }
    end

    scores = factors.values.map { |f| confidence_to_numeric(f[:level] || f[:label]) }.compact
    overall = scores.any? ? (scores.sum / scores.size).round(1) : 0

    {
      factors: factors,
      overall: overall,
      label: confidence_level(overall)
    }
  end

  private

  def confidence_level(count)
    case count.to_i
    when 50.. then "HIGH"
    when 20..49 then "MODERATE"
    when 5..19 then "LOW"
    else "MINIMAL"
    end
  end

  def confidence_to_numeric(level)
    {
      "HIGH" => 90, "TRUSTED" => 90, "RELIABLE" => 75, "MODERATE" => 60,
      "MIXED" => 50, "LOW" => 30, "QUESTIONABLE" => 20, "MINIMAL" => 10,
      "UNRELIABLE" => 5, "UNKNOWN" => 0
    }[level.to_s] || 0
  end
end
