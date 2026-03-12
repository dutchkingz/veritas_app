# frozen_string_literal: true

# ---------------------------------------------------------------
# RegionalAnalysisService
#
# Fetches the latest 30 articles for a region published in the
# last 48 hours, builds a consolidated prompt, and calls
# OpenRouter to generate a single intelligence report.
#
# Usage:
#   RegionalAnalysisService.call(report)
#     where `report` is a persisted IntelligenceReport record.
# ---------------------------------------------------------------
class RegionalAnalysisService
  ARTICLE_LIMIT = 30

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
      @report.update!(status: "failed", summary: "No signals detected for #{@region.name} within the 48h active window.")
      return @report
    end

    @report.update!(
      status: "processing",
      analyzed_article_ids: articles.pluck(:id)
    )

    summary = generate_report(articles)

    @report.update!(status: "completed", summary: summary)
    @report
  rescue StandardError => e
    @report.update!(status: "failed", summary: "CRITICAL SYSTEM FAILURE: #{e.message}")
    raise
  end

  private

  def fetch_articles
    Article
      .by_region_name(@region.name)
      .recent_48h
      .order(published_at: :desc)
      .limit(ARTICLE_LIMIT)
  end

  def generate_report(articles)
    system_prompt = <<~SYSTEM
      You are VERITAS, a principal OSINT analyst on a defense-grade intelligence platform.
      Your task is to synthesize disparate news signals into a cohesive, high-density 
      intelligence briefing. 
      
      Precision and neutrality are paramount. Avoid flowery language; use technical 
      intelligence terminology.
    SYSTEM

    user_prompt = build_user_prompt(articles)

    # Switching to :analyst (Gemini 2.0 Flash) for better reasoning on multi-source data
    @client.chat(:analyst, system_prompt, user_prompt, expect_json: false)
  end

  def build_user_prompt(articles)
    formatted = articles.each_with_index.map do |article, idx|
      # FIXED: Using .to_s.first(500) instead of ActionView's .truncate() which isn't available here
      content_snippet = article.content.to_s.first(500).gsub(/\s+/, ' ')
      <<~ENTRY
        SIGNAL [#{idx + 1}]
        SOURCE: #{article.source_name}
        TIMESTAMP: #{article.published_at&.iso8601}
        TITLE: #{article.headline}
        DATA: #{content_snippet}...
      ENTRY
    end.join("\n---\n")

    <<~PROMPT
      GEOPOLITICAL REGION: #{@region.name}
      ACTIVE WINDOW: 48 Hours
      SIGNAL COUNT: #{articles.size}

      ## RAW SIGNAL DATA
      #{formatted}

      ## OBJECTIVE
      Generate a "VERITAS Intelligence Briefing" (Markdown format). 

      ### 1. NARRATIVE LANDSCAPE
      Summarize the primary narrative arc. Is this a coordinated information operation, 
      or a series of independent events?

      ### 2. CORE THEMES
      Identify 3-5 recurring thematic pillars across sources.

      ### 3. CROSS-SOURCE ANOMALIES
      Identify any "outlier" sources that contradict the dominant regional narrative. 
      Flag potential disinformation or unique scoops.

      ### 4. GEOPOLITICAL IMPACT
      How do these signals shift the regional stability? Provide a 1-sentence projection.

      ### 5. VERDICT
      Set current threat level: [STABLE / GUARDED / ELEVATED / SEVERE].
    PROMPT
  end
end
