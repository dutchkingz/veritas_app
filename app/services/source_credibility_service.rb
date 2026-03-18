class SourceCredibilityService
  def update_for(article)
    return unless article.ai_analysis&.analysis_status == "complete"
    return if article.source_name.blank?

    credibility = SourceCredibility.find_or_create_by!(source_name: article.source_name)
    credibility.ingest_analysis!(article.ai_analysis)

    Rails.logger.info "[CREDIBILITY] #{article.source_name}: grade=#{credibility.credibility_grade} " \
                      "trust=#{credibility.rolling_trust_score.round(2)} " \
                      "(#{credibility.articles_analyzed} articles, #{credibility.grade_label})"
  rescue StandardError => e
    Rails.logger.error "[CREDIBILITY] Failed for Article ##{article.id}: #{e.message}"
  end
end
