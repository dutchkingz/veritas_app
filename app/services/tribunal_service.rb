# TribunalService
#
# Synthesizes a three-agent "live debate" from the stored JSON responses
# in AiAnalysis — no new LLM calls required. Each agent's reasoning,
# findings, and verdict are composed into prose statements for the
# War Room Tribunal panel typewriter sequence.
#
# Usage: TribunalService.new(article).call
# Returns: { status:, article:, turns: [] }

class TribunalService
  AGENT_META = {
    analyst: {
      name:  "AGENT ANALYST",
      model: "Gemini 2.0 Flash",
      color: "#00d4ff",
      icon:  "◎"
    },
    sentinel: {
      name:  "AGENT SENTINEL",
      model: "GPT-4o-mini",
      color: "#f59e0b",
      icon:  "⬡"
    },
    arbiter: {
      name:  "AGENT ARBITER",
      model: "Claude Haiku",
      color: "#a78bfa",
      icon:  "⬟"
    }
  }.freeze

  THREAT_COLORS = {
    "CRITICAL"   => "#ef4444",
    "HIGH"       => "#f97316",
    "MODERATE"   => "#eab308",
    "LOW"        => "#22c55e",
    "NEGLIGIBLE" => "#38bdf8"
  }.freeze

  def initialize(article)
    @article  = article
    @analysis = article.ai_analysis
  end

  def call
    return not_ready_result unless @analysis&.analysis_status == "complete"

    {
      status:  "ready",
      article: article_meta,
      turns:   [analyst_turn, sentinel_turn, arbiter_turn].compact
    }
  end

  private

  # -------------------------------------------------------
  # Agent turn builders
  # -------------------------------------------------------

  def analyst_turn
    r = @analysis.analyst_response || {}

    trust     = r["trust_score"]
    sentiment = r["sentiment_label"]
    topic     = r["geopolitical_topic"]
    reasoning = r["reasoning"].presence

    parts = []
    parts << "Analyzing signal from #{@article.source_name}#{@article.country ? ", #{@article.country.name}" : ""}."
    parts << "Primary domain: #{topic}." if topic.present?
    parts << "Signal sentiment: #{sentiment}. Source reliability: #{trust}/100." if sentiment && trust
    parts << reasoning if reasoning

    build_turn(:analyst, parts.join(" "))
  end

  def sentinel_turn
    r = @analysis.sentinel_response || {}

    flag         = r["linguistic_anomaly_flag"]
    notes        = r["anomaly_notes"].presence
    bias         = r["bias_direction"].presence
    techniques   = Array(r["propaganda_techniques"]).compact.reject(&:empty?)
    credibility  = r["source_credibility"].presence
    ind_trust    = r["independent_trust_score"]
    reasoning    = r["reasoning"].presence

    parts = []
    parts << "Independent forensic cross-check complete."
    parts << "Bias direction: #{bias}." if bias
    parts << "Source credibility rating: #{credibility}." if credibility
    parts << "Independent trust score: #{ind_trust}/100." if ind_trust

    if flag
      parts << "⚠ Linguistic anomalies detected."
      parts << "Techniques identified: #{techniques.join(', ')}." if techniques.any?
      parts << notes if notes
    else
      parts << (notes || "No significant anomalies detected.")
    end

    parts << reasoning if reasoning && reasoning != notes

    build_turn(:sentinel, parts.join(" "))
  end

  def arbiter_turn
    r = @analysis.arbiter_response || {}

    final_trust   = r["final_trust_score"]
    final_summary = clean(r["final_summary"])
    agreement     = r["agreement_level"].presence
    arb_notes     = clean(r["arbitration_notes"])
    anomaly_flag  = r["linguistic_anomaly_flag"]
    threat        = r["final_threat_level"].presence

    agreement_str = case agreement
                    when "FULL_CONSENSUS"           then "Both agents reached full consensus."
                    when "PARTIAL_AGREEMENT"        then "Agents reached partial agreement."
                    when "SIGNIFICANT_DISAGREEMENT" then "Significant disagreement detected — weighted judgment applied."
                    end # unknown/mock values are simply skipped

    parts = []
    parts << agreement_str if agreement_str.present?
    parts << "VERDICT: #{final_summary}" if final_summary
    parts << arb_notes if arb_notes
    parts << "Manipulation flag: #{anomaly_flag ? 'ACTIVE' : 'CLEAR'}." unless anomaly_flag.nil?
    parts << "Final trust score: #{final_trust}/100. Threat assessment: #{threat}." if final_trust && threat

    build_turn(:arbiter, parts.join(" "))
  end

  # -------------------------------------------------------
  # Helpers
  # -------------------------------------------------------

  # Returns nil if the string looks like placeholder/seed data
  MOCK_PATTERNS = /mock|placeholder|lorem|fast init|generated for|sample data|test data/i.freeze

  def clean(value)
    str = value.presence
    return nil if str.nil?
    return nil if str.match?(MOCK_PATTERNS)
    str
  end

  def build_turn(agent, message)
    AGENT_META[agent].merge(
      agent:   agent.to_s,
      message: message.squish
    )
  end

  def article_meta
    threat  = @analysis.threat_level.to_s.upcase
    {
      headline:     @article.headline,
      source:       @article.source_name,
      threat_level: threat.presence || "UNKNOWN",
      threat_color: THREAT_COLORS[threat] || "#6b7280",
      trust_score:  @analysis.trust_score.to_i
    }
  end

  def not_ready_result
    {
      status:          "not_ready",
      analysis_status: @analysis&.analysis_status || "pending",
      article_id:      @article.id
    }
  end
end
