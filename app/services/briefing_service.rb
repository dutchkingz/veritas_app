class BriefingService
  def initialize(user)
    @user   = user
    @client = OpenRouterClient.new
  end

  def generate
    convergences = NarrativeConvergence.active.recent.limit(5)
    high_threat  = recent_high_threat_articles
    outliers     = NarrativeConvergenceService.new.top_outliers(limit: 3)
    wl_hits      = watchlist_hit_count

    context = build_context(convergences, high_threat, outliers, wl_hits)

    system_prompt = <<~SYS
      You are the VERITAS Intelligence Briefing System.
      Generate a structured daily intelligence dossier from the provided data.

      Use EXACTLY these section headers (markdown ## style):
      ## EXECUTIVE SUMMARY
      ## ACTIVE NARRATIVE OPERATIONS
      ## HIGH-PRIORITY SIGNALS
      ## UNIQUE INTELLIGENCE
      ## ANALYST RECOMMENDATIONS

      Rules:
      - Executive Summary: 2-3 sentences on the current geopolitical threat environment.
      - Narrative Operations: what the convergence clusters mean. Reference [C1], [C2].
      - High-Priority Signals: most critical individual articles. Reference [S1], [S2].
      - Unique Intelligence: isolated outlier signals worth investigating. Reference [U1].
      - Recommendations: exactly 3 specific, actionable steps for the analyst today.
      - Total: max 450 words. Tone: authoritative, Palantir-grade, zero filler.
    SYS

    briefing_text = @client.chat(:arbiter, system_prompt, context, expect_json: false)

    narratives_json = convergences.map { |c|
      { label: c.label, threat: c.dominant_threat_level, article_count: c.article_count }
    }.to_json

    Briefing.create!(
      user:           @user,
      threat_summary: briefing_text,
      top_narratives: narratives_json,
      generated_at:   Time.current
    )
  rescue StandardError => e
    Rails.logger.error "[BRIEFING] Generation failed: #{e.message}"
    nil
  end

  private

  def build_context(convergences, high_threat, outliers, wl_hits)
    lines = ["VERITAS INTELLIGENCE BRIEFING DATA — #{Date.current.strftime('%B %d, %Y')}"]

    lines << "\n### ACTIVE CONVERGENCES (#{convergences.count} coordinated narrative clusters):"
    if convergences.any?
      convergences.each_with_index do |c, i|
        lines << "[C#{i + 1}] #{c.label}"
        lines << "     Outlets: #{c.source_names.first(3).join(', ')} | Countries: #{c.countries.first(5).join(' · ')}"
        lines << "     Threat: #{c.dominant_threat_level} | #{c.article_count} articles | Diversity: #{c.convergence_percentage.round}%"
      end
    else
      lines << "No active convergences detected."
    end

    lines << "\n### HIGH-THREAT SIGNALS (last 24h):"
    if high_threat.any?
      high_threat.each_with_index do |a, i|
        lines << "[S#{i + 1}] #{a.ai_analysis.threat_level} | #{a.source_name} (#{a.country&.iso_code}): #{a.headline}"
        lines << "     Trust Score: #{a.ai_analysis.trust_score.to_i}/100"
      end
    else
      lines << "No CRITICAL/HIGH threat signals in the past 24 hours."
    end

    lines << "\n### UNIQUE SIGNALS (isolated — not part of any convergence cluster):"
    if outliers.any?
      outliers.each_with_index do |a, i|
        lines << "[U#{i + 1}] #{a.ai_analysis.threat_level} | #{a.source_name}: #{a.headline}"
      end
    else
      lines << "No high-threat isolated signals."
    end

    lines << "\n### WATCHLIST: #{wl_hits} new article(s) matched the analyst's saved signatures in the last 7 days."

    lines.join("\n")
  end

  def recent_high_threat_articles
    Article.joins(:ai_analysis)
           .where(published_at: 24.hours.ago..Time.current)
           .where(ai_analyses: { threat_level: %w[CRITICAL HIGH], analysis_status: 'complete' })
           .includes(:ai_analysis, :country)
           .order('ai_analyses.trust_score DESC')
           .limit(5)
  end

  def watchlist_hit_count
    saved_ids = @user.saved_articles.pluck(:article_id).compact
    return 0 if saved_ids.empty?

    sig_articles = Article.where(id: saved_ids).select { |a| a.embedding.present? }
    sig_articles.sum do |sig|
      Article.joins(:ai_analysis)
             .where.not(id: saved_ids)
             .where(published_at: 7.days.ago..Time.current)
             .where(ai_analyses: { analysis_status: 'complete' })
             .nearest_neighbors(:embedding, sig.embedding, distance: "cosine")
             .limit(5)
             .to_a
             .count { |a| a.neighbor_distance < 0.25 }
    end
  rescue StandardError
    0
  end
end
