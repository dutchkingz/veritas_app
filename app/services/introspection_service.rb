class IntrospectionService
  def initialize
    @client = OpenRouterClient.new
  end

  def generate_daily_brief
    brief = IntelligenceBrief.create!(
      brief_type: "daily",
      title: "VERITAS Daily Intelligence Brief — #{Date.current.strftime('%d %b %Y')}",
      period_start: 24.hours.ago,
      period_end: Time.current,
      status: "generating"
    )

    Rails.logger.info "[INTROSPECTION] Generating daily brief..."

    narrative_trends   = analyze_narrative_trends
    source_alerts      = analyze_source_changes
    contradictions     = recent_contradictions
    blind_spots        = detect_blind_spots
    confidence_map     = build_confidence_map

    executive_summary = generate_executive_summary(
      narrative_trends, source_alerts, contradictions, blind_spots
    )

    brief.update!(
      executive_summary:    executive_summary,
      narrative_trends:     narrative_trends,
      source_alerts:        source_alerts,
      contradictions:       contradictions,
      blind_spots:          blind_spots,
      confidence_map:       confidence_map,
      articles_processed:   Article.where(created_at: 24.hours.ago..).count,
      signatures_active:    NarrativeSignature.active.count,
      contradictions_found: ContradictionLog.where(created_at: 24.hours.ago..).count,
      status:               "complete"
    )

    Rails.logger.info "[INTROSPECTION] Daily brief complete: '#{brief.title}'"
    brief
  rescue StandardError => e
    brief&.update(status: "failed")
    Rails.logger.error "[INTROSPECTION] Brief generation failed: #{e.message}"
    raise e
  end

  private

  def analyze_narrative_trends
    NarrativeSignature.active.map do |sig|
      recent   = sig.narrative_signature_articles.where(matched_at: 24.hours.ago..).count
      previous = sig.narrative_signature_articles.where(matched_at: 48.hours.ago..24.hours.ago).count
      delta = recent - previous
      direction = delta.positive? ? "RISING" : (delta.negative? ? "FALLING" : "STABLE")

      {
        label: sig.label,
        match_count: sig.match_count,
        recent: recent,
        delta: delta,
        direction: direction,
        avg_trust: sig.avg_trust_score.round(1),
        threat: sig.dominant_threat_level,
        sources: sig.source_distribution.size
      }
    end.sort_by { |t| -t[:recent] }
  end

  def analyze_source_changes
    SourceCredibility.where(last_analyzed_at: 24.hours.ago..).map do |sc|
      {
        source: sc.source_name,
        grade: sc.credibility_grade.round(1),
        label: sc.grade_label,
        articles: sc.articles_analyzed,
        trust: sc.rolling_trust_score.round(1)
      }
    end.sort_by { |s| -s[:grade] }
  end

  def recent_contradictions
    ContradictionLog.where(created_at: 24.hours.ago..).severe.limit(10).map do |cl|
      {
        type: cl.contradiction_type,
        source_a: cl.source_a,
        source_b: cl.source_b,
        description: cl.description,
        severity: cl.severity
      }
    end
  end

  def detect_blind_spots
    Region.all.filter_map do |region|
      count = Article.where(region: region, published_at: 7.days.ago..).count
      sources = Article.where(region: region, published_at: 7.days.ago..).distinct.count(:source_name)
      if count < 5
        { region: region.name, article_count: count, source_count: sources, status: "LOW_COVERAGE" }
      end
    end
  end

  def build_confidence_map
    topics = AiAnalysis.where(analysis_status: "complete")
                       .where.not(geopolitical_topic: [nil, ""])
                       .group(:geopolitical_topic)
                       .count

    topics.transform_values do |count|
      case count
      when 50.. then "HIGH"
      when 20..49 then "MODERATE"
      when 5..19 then "LOW"
      else "MINIMAL"
      end
    end
  end

  def generate_executive_summary(trends, source_alerts, contradictions, blind_spots)
    rising  = trends.select { |t| t[:direction] == "RISING" }.first(5)
    falling = trends.select { |t| t[:direction] == "FALLING" }.first(3)
    stable  = trends.select { |t| t[:direction] == "STABLE" }.first(3)

    context = <<~CTX
      VERITAS SYSTEM STATE — #{Date.current.strftime('%d %B %Y')}

      ACTIVE SIGNATURES: #{NarrativeSignature.active.count}
      TOTAL ARTICLES ANALYZED: #{Article.joins(:ai_analysis).where(ai_analyses: { analysis_status: "complete" }).count}
      SOURCE PROFILES: #{SourceCredibility.count} sources tracked

      RISING NARRATIVES: #{rising.any? ? rising.map { |t| "#{t[:label]} (+#{t[:delta]}, #{t[:sources]} sources)" }.join("; ") : "None detected"}
      FALLING NARRATIVES: #{falling.any? ? falling.map { |t| "#{t[:label]} (#{t[:delta]})" }.join("; ") : "None detected"}
      STABLE NARRATIVES: #{stable.any? ? stable.map { |t| "#{t[:label]} (#{t[:match_count]} total articles)" }.join("; ") : "None detected"}

      CONTRADICTIONS DETECTED (24h): #{contradictions.size}#{contradictions.any? ? " — " + contradictions.map { |c| "#{c[:source_a]}: #{c[:description]&.truncate(80)}" }.join("; ") : ""}

      SOURCE ALERTS: #{source_alerts.size} sources updated in last 24h
      #{source_alerts.first(5).map { |s| "#{s[:source]}: #{s[:label]} (grade #{s[:grade]}, #{s[:articles]} articles)" }.join("\n")}

      BLIND SPOTS: #{blind_spots.any? ? blind_spots.map { |b| "#{b[:region]} (#{b[:article_count]} articles, #{b[:source_count]} sources)" }.join("; ") : "No coverage gaps detected"}
    CTX

    system = <<~SYS
      You are VERITAS, an autonomous intelligence platform that monitors global narrative warfare.
      Write a 2-3 paragraph executive briefing summarizing today's intelligence landscape.
      Be direct, analytical, and specific. Flag anything that warrants analyst attention.
      Write in first person as the system — you ARE the intelligence platform speaking.
      Do not hedge or qualify excessively. State what you know and what you don't.
    SYS

    @client.chat(:arbiter, system, context, expect_json: false)
  end
end
