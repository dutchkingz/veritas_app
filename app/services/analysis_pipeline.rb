class AnalysisPipeline
  def initialize
    @analyst  = AnalystAgent.new
    @sentinel = SentinelAgent.new
    @arbiter  = ArbiterAgent.new
  end

  def analyze(article)
    analysis = article.with_lock do
      current = article.ai_analysis || article.build_ai_analysis
      return current if current.analysis_status == 'complete'
      return current if current.analysis_status == 'analyzing'

      current.update!(analysis_status: 'analyzing')
      current
    end

    Rails.logger.info "[VERITAS TRIAD] Starting analysis pipeline for Article ##{article.id}"

    begin
      # ━━━ PHASE 1: Parallel Independent Analysis ━━━
      # Agent 1 (Gemini Flash) — Content analysis
      Rails.logger.info "[VERITAS TRIAD] Agent ANALYST (Gemini Flash) processing..."
      analyst_result = @analyst.analyze(article)
      analysis.update!(analyst_response: analyst_result)
      Rails.logger.info "[VERITAS TRIAD] Agent ANALYST complete. Trust: #{analyst_result['trust_score']}"

      # Agent 2 (GPT-4o-mini) — Independent forensic check
      Rails.logger.info "[VERITAS TRIAD] Agent SENTINEL (GPT-4o-mini) processing..."
      sentinel_result = @sentinel.analyze(article)
      analysis.update!(sentinel_response: sentinel_result)
      Rails.logger.info "[VERITAS TRIAD] Agent SENTINEL complete. Trust: #{sentinel_result['independent_trust_score']}"

      # ━━━ PHASE 2: Cross-Verification ━━━
      # Agent 3 (Claude Haiku) — Judges both reports
      Rails.logger.info "[VERITAS TRIAD] Agent ARBITER (Claude Haiku) cross-verifying..."
      arbiter_result = @arbiter.arbitrate(article, analyst_result, sentinel_result)
      analysis.update!(arbiter_response: arbiter_result)
      Rails.logger.info "[VERITAS TRIAD] Agent ARBITER complete. Final trust: #{arbiter_result['final_trust_score']}"

      # ━━━ PHASE 3: Final Record ━━━
      analysis.update!(
        trust_score: arbiter_result['final_trust_score'].to_f,
        sentiment_label: arbiter_result['final_sentiment_label'],
        sentiment_color: arbiter_result['final_sentiment_color'],
        threat_level: arbiter_result['final_threat_level'],
        summary: arbiter_result['final_summary'],
        geopolitical_topic: arbiter_result['final_geopolitical_topic'],
        linguistic_anomaly_flag: arbiter_result['linguistic_anomaly_flag'],
        anomaly_notes: arbiter_result['anomaly_notes'],
        analysis_status: 'complete'
      )

      Rails.logger.info "[VERITAS TRIAD] ✅ Analysis pipeline COMPLETE for Article ##{article.id}"

      # ━━━ PHASE 3b: Source Credibility Update ━━━
      SourceCredibilityService.new.update_for(article)

      # ━━━ PHASE 4: Semantic Intelligence (Vector Embedding) ━━━
      EmbeddingService.new.generate(article)

      # ━━━ PHASE 4b: Narrative Signature Classification ━━━
      NarrativeSignatureService.new.classify(article)

      # ━━━ PHASE 5: Entity Extraction (non-blocking) ━━━
      begin
        EntityExtractionService.new.extract(article)
      rescue StandardError => e
        Rails.logger.warn "[VERITAS TRIAD] Entity extraction skipped for Article ##{article.id}: #{e.message}"
      end

      analysis
    rescue StandardError => e
      Rails.logger.error "[VERITAS TRIAD] ❌ Pipeline FAILED for Article ##{article.id}: #{e.message}"
      analysis.update!(analysis_status: 'failed', anomaly_notes: "Pipeline error: #{e.message}")
      raise e
    end
  end
end
