# frozen_string_literal: true

# ---------------------------------------------------------------
# RegionalAnalysisService — Phase 3
#
# Generates a Palantir-grade regional intelligence briefing:
#
#   1. Fetches only Triad-verified articles (analysis_status = complete)
#   2. Computes signal_stats: trust distribution, source diversity,
#      anomaly rates, top sources (persisted to DB for delta comparison)
#   3. Temporal bucketing: splits 48h into 4×12h windows to surface
#      narrative escalation/de-escalation patterns
#   4. Pulls active NarrativeConvergences for the region
#   5. Calls the Arbiter (Claude Haiku) for cross-verified synthesis
#   6. Extracts and stores the verdict separately for UI use
#
# Usage:
#   RegionalAnalysisService.call(report)
# ---------------------------------------------------------------
class RegionalAnalysisService
  ARTICLE_LIMIT  = 30
  BUCKET_HOURS   = 12    # 48h window split into 4 × 12h buckets
  BUCKET_COUNT   = 4

  def self.call(report)
    new(report).call
  end

  def initialize(report)
    @report = report
    @region = report.region
    @client = OpenRouterClient.new
  end

  def call
    articles = fetch_articles

    if articles.empty?
      @report.update!(
        status:  "failed",
        summary: "No verified signals detected for #{@region.name} within the 48h active window. " \
                 "Ensure articles have completed AI analysis before running regional briefings."
      )
      return @report
    end

    @report.update!(
      status:               "processing",
      analyzed_article_ids: articles.pluck(:id)
    )

    stats        = compute_signal_stats(articles)
    convergences = fetch_regional_convergences
    summary, verdict = generate_report(articles, stats, convergences)

    @report.update!(
      status:       "completed",
      summary:      summary,
      verdict:      verdict,
      signal_stats: stats
    )
    @report
  rescue StandardError => e
    @report.update!(status: "failed", summary: "CRITICAL SYSTEM FAILURE: #{e.message}")
    raise
  end

  private

  # ---------------------------------------------------------------
  # Data Fetching
  # ---------------------------------------------------------------

  def fetch_articles
    Article
      .by_region_name(@region.name)
      .recent_48h
      .joins(:ai_analysis)
      .where(ai_analyses: { analysis_status: "complete" })
      .includes(:ai_analysis, :country)
      .order("ai_analyses.trust_score ASC NULLS LAST, articles.published_at DESC")
      .limit(ARTICLE_LIMIT)
  end

  def fetch_regional_convergences
    country_names = @region.countries.pluck(:name)
    return [] if country_names.empty?

    NarrativeConvergence.active.select { |nc| (nc.countries & country_names).any? }
  rescue StandardError
    []
  end

  # ---------------------------------------------------------------
  # Signal Stats — persisted to DB for historical delta comparison
  # ---------------------------------------------------------------

  def compute_signal_stats(articles)
    trust_scores  = articles.map { |a| a.ai_analysis.trust_score || 0 }
    threat_labels = articles.map { |a| normalize_threat(a.ai_analysis.threat_level) }
    anomaly_flags = articles.map { |a| anomaly_flag_for(a.ai_analysis) }

    source_counts = articles.group_by(&:source_name).transform_values(&:count)
    top_sources   = source_counts.sort_by { |_, c| -c }.first(5).map { |n, c| { "name" => n, "count" => c } }

    trust_dist = {
      "low"       => trust_scores.count { |t| t < 40 },
      "medium"    => trust_scores.count { |t| t >= 40 && t < 60 },
      "high"      => trust_scores.count { |t| t >= 60 && t < 80 },
      "very_high" => trust_scores.count { |t| t >= 80 }
    }

    {
      "avg_trust"        => (trust_scores.sum.to_f / articles.size).round(1),
      "source_diversity" => source_counts.keys.size,
      "anomaly_count"    => anomaly_flags.count(&:itself),
      "anomaly_pct"      => ((anomaly_flags.count(&:itself).to_f / articles.size) * 100).round(1),
      "critical_count"   => threat_labels.count("CRITICAL"),
      "high_count"       => threat_labels.count("HIGH"),
      "high_pct"         => ((threat_labels.count { |t| %w[HIGH CRITICAL].include?(t) }.to_f / articles.size) * 100).round(1),
      "top_sources"      => top_sources,
      "trust_distribution" => trust_dist,
      "temporal_buckets"   => compute_temporal_buckets(articles)
    }
  end

  # Split articles into 4 × 12h windows from oldest to newest.
  # Each bucket captures escalation/de-escalation within the 48h window.
  def compute_temporal_buckets(articles)
    now      = Time.now
    buckets  = BUCKET_COUNT.times.map do |i|
      end_time   = now - (i * BUCKET_HOURS.hours)
      start_time = now - ((i + 1) * BUCKET_HOURS.hours)
      label      = i.zero? ? "T-12h → NOW" : "T-#{(i + 1) * BUCKET_HOURS}h → T-#{i * BUCKET_HOURS}h"
      { label: label, start: start_time, end: end_time, articles: [] }
    end.reverse  # Chronological order: oldest first

    articles.each do |article|
      pub = article.published_at || article.created_at
      bucket = buckets.find { |b| pub >= b[:start] && pub < b[:end] }
      bucket[:articles] << article if bucket
    end

    buckets.map do |b|
      arts         = b[:articles]
      trust_scores = arts.map { |a| a.ai_analysis.trust_score || 0 }
      threats      = arts.map { |a| normalize_threat(a.ai_analysis.threat_level) }
      anomalies    = arts.count { |a| anomaly_flag_for(a.ai_analysis) }
      avg_trust    = arts.empty? ? nil : (trust_scores.sum.to_f / arts.size).round(1)

      {
        "label"         => b[:label],
        "count"         => arts.size,
        "avg_trust"     => avg_trust,
        "high_count"    => threats.count { |t| %w[HIGH CRITICAL].include?(t) },
        "anomaly_count" => anomalies
      }
    end
  end

  # ---------------------------------------------------------------
  # LLM Generation
  # ---------------------------------------------------------------

  def generate_report(articles, stats, convergences)
    system_prompt = <<~SYSTEM
      You are VERITAS ARBITER, a principal OSINT analyst on a defense-grade intelligence platform.
      You have access to AI-verified signals — each pre-processed by a three-agent pipeline
      (Analyst, Sentinel, Arbiter) that has assigned trust scores, threat levels, bias
      directions, and linguistic anomaly flags.

      You also have temporal analysis data showing how the narrative evolved over 48 hours
      in 12-hour buckets. Use this to detect escalation patterns.

      Your job: synthesize verified signals into a cohesive, high-density regional briefing.
      Cite specific signals by number. Be precise, neutral, and technical.

      You MUST end your response with a verdict line in exactly this format:
      VERDICT: STABLE
      (replace STABLE with GUARDED, ELEVATED, or SEVERE as appropriate)
    SYSTEM

    user_prompt = build_user_prompt(articles, stats, convergences)
    raw         = @client.chat(:arbiter, system_prompt, user_prompt, expect_json: false)

    verdict = extract_verdict(raw)
    summary = raw.sub(/\n*VERDICT:\s*(STABLE|GUARDED|ELEVATED|SEVERE)\s*$/i, "").strip

    [ summary, verdict ]
  end

  def build_user_prompt(articles, stats, convergences)
    <<~PROMPT
      GEOPOLITICAL REGION: #{@region.name}
      ACTIVE WINDOW: 48 Hours
      VERIFIED SIGNAL COUNT: #{articles.size}
      UNIQUE SOURCES: #{stats["source_diversity"]}
      REGIONAL AVG TRUST: #{stats["avg_trust"]}/100
      HIGH/CRITICAL SIGNALS: #{stats["critical_count"] + stats["high_count"]} (#{stats["critical_count"]} CRITICAL, #{stats["high_count"]} HIGH, #{stats["high_pct"]}%)
      ANOMALY FLAGS: #{stats["anomaly_count"]} signals (#{stats["anomaly_pct"]}%)
      #{format_convergences(convergences)}
      #{format_temporal_buckets(stats["temporal_buckets"])}
      ## VERIFIED SIGNAL INTELLIGENCE
      #{format_signals(articles)}

      ## ANALYTICAL OBJECTIVE
      Generate a "VERITAS Regional Intelligence Briefing" in Markdown format.

      ### 1. NARRATIVE LANDSCAPE
      Dominant narrative arc? Is this organic reporting or coordinated messaging?
      Reference specific trust scores and anomaly flags. Note any temporal escalation patterns.

      ### 2. CORE THEMES
      3-5 recurring thematic pillars. Note source diversity per theme — single-source themes warrant scrutiny.

      ### 3. CROSS-SOURCE ANOMALIES
      Flag signals contradicting the dominant narrative or carrying anomaly flags.
      Explicitly call out any sources with trust score below 40.

      ### 4. TEMPORAL EVOLUTION
      Analyze the 12-hour bucket data. Is the narrative escalating, de-escalating, or stable?
      Identify any inflection points between buckets.

      ### 5. CONVERGENCE INTELLIGENCE
      Analyze active convergences. Amplification operation or organic clustering?
      If none: state "No active convergence patterns detected."

      ### 6. GEOPOLITICAL IMPACT
      How do these signals shift regional stability? 1-2 sentence projection.

      ### 7. ANALYST VERDICT
      Assign threat level with one-paragraph justification.
      Close with exactly:
      VERDICT: [STABLE|GUARDED|ELEVATED|SEVERE]
    PROMPT
  end

  # ---------------------------------------------------------------
  # Prompt Formatters
  # ---------------------------------------------------------------

  def format_signals(articles)
    articles.each_with_index.map do |article, idx|
      analysis     = article.ai_analysis
      content      = article.content.presence ||
                     article.raw_data&.dig("description").presence ||
                     article.headline
      snippet      = content.to_s.gsub(/\s+/, " ").first(600)
      anomaly_flag = anomaly_flag_for(analysis)
      anomaly_notes = analysis.anomaly_notes.presence || (anomaly_flag ? "Flagged by Sentinel" : nil)
      anomaly_line  = anomaly_flag ?
                      "  ⚠ ANOMALY FLAGGED: #{anomaly_notes}" :
                      "  ANOMALY: None"

      <<~ENTRY
        SIGNAL [#{idx + 1}]
        SOURCE: #{article.source_name} | COUNTRY: #{article.country&.name}
        TIMESTAMP: #{article.published_at&.iso8601}
        TITLE: #{article.headline}
        TRUST_SCORE: #{analysis.trust_score&.round(1)}/100 | THREAT: #{normalize_threat(analysis.threat_level)}
        SENTIMENT: #{analysis.sentiment_label} | TOPIC: #{geopolitical_topic_for(analysis)}
        BIAS: #{analysis.sentinel_response&.dig("bias_direction") || "UNKNOWN"}
        #{anomaly_line}
        EXCERPT: #{snippet}
      ENTRY
    end.join("\n---\n")
  end

  def format_convergences(convergences)
    header = "\n## ACTIVE NARRATIVE CONVERGENCES"
    return "#{header}\n  None detected.\n" if convergences.empty?

    lines = convergences.map do |nc|
      avg = nc.avg_trust_score&.round(1) || "N/A"
      "  • [#{nc.dominant_threat_level}] \"#{nc.label}\" — #{nc.article_count} articles, " \
      "#{nc.countries.size} countries, avg trust: #{avg}"
    end
    "#{header}\n#{lines.join("\n")}\n"
  end

  def format_temporal_buckets(buckets)
    return "" if buckets.blank?

    lines = buckets.map do |b|
      trust_str = b["avg_trust"] ? "avg trust #{b["avg_trust"]}" : "no data"
      "  #{b["label"].ljust(22)} | #{b["count"].to_s.rjust(2)} signals | #{trust_str} | " \
      "#{b["high_count"]} high/crit | #{b["anomaly_count"]} anomalies"
    end

    "\n## TEMPORAL EVOLUTION (48h → 4×12h buckets)\n#{lines.join("\n")}\n"
  end

  # ---------------------------------------------------------------
  # Normalization helpers (handle seed/mock data with numeric levels)
  # ---------------------------------------------------------------

  THREAT_LABEL_MAP = {
    "1" => "LOW", "2" => "MODERATE", "3" => "HIGH",
    "4" => "CRITICAL", "5" => "CRITICAL"
  }.freeze

  def normalize_threat(level)
    return level if level.nil?
    THREAT_LABEL_MAP[level.to_s] || level.to_s.upcase
  end

  def geopolitical_topic_for(analysis)
    analysis.geopolitical_topic.presence ||
      analysis.analyst_response&.dig("geopolitical_topic").presence ||
      "UNCLASSIFIED"
  end

  def anomaly_flag_for(analysis)
    return analysis.linguistic_anomaly_flag unless analysis.linguistic_anomaly_flag.nil?
    analysis.sentinel_response&.dig("linguistic_anomaly_flag")
  end

  def extract_verdict(text)
    match = text.match(/VERDICT:\s*(STABLE|GUARDED|ELEVATED|SEVERE)/i)
    match ? match[1].upcase : nil
  end
end
