class RagAgent
  def initialize
    @client = OpenRouterClient.new
  end

  def ask(user_query, history: [])
    # 1. Embed the user's question
    query_vector = @client.embed(user_query)

    return { response: "Error: Could not generate semantic vector.", sources: [] } unless query_vector

    # 2. Fetch 20 candidates — filter pushed to DB via JOIN (fixes starvation bug)
    candidates = Article
      .joins(:ai_analysis)
      .where.not(embedding: nil)
      .where.not(published_at: nil)
      .where.not(ai_analyses: { summary: [nil, ''] })
      .where(ai_analyses: { analysis_status: 'complete' })
      .nearest_neighbors(:embedding, query_vector, distance: "cosine")
      .limit(20)

    # 3. Re-rank by composite score (proximity × trust × recency × threat)
    ranked = candidates.each_with_index.sort_by do |article, idx|
      analysis  = article.ai_analysis
      proximity = 1.0 / (1.0 + idx * 0.1)
      trust     = 0.5 + (analysis.trust_score.to_f.clamp(0, 100) / 100.0)
      recency   = article.published_at >= 7.days.ago  ? 1.20 :
                  article.published_at >= 30.days.ago ? 1.10 : 1.0
      threat    = { 'CRITICAL' => 1.15, 'HIGH' => 1.10, 'MODERATE' => 1.05 }
                    .fetch(analysis.threat_level, 1.0)
      -(proximity * trust * recency * threat)
    end.map(&:first).first(8)

    # 4. Source diversity — max 2 per source_name, keep top 5
    source_counts = Hash.new(0)
    final_articles = ranked.each_with_object([]) do |article, result|
      next if source_counts[article.source_name] >= 2
      result << article
      source_counts[article.source_name] += 1
      break result if result.size >= 5
    end

    return { response: "No relevant intelligence found.", sources: [] } if final_articles.empty?

    # 5. Build context block
    context_builder = ["AVAILABLE INTELLIGENCE CONTEXT:"]
    final_articles.each_with_index do |article, i|
      context_builder << "---"
      context_builder << "SOURCE [#{i + 1}]: #{article.source_name} (#{article.country&.iso_code || 'GLOBAL'})"
      context_builder << "HEADLINE: #{article.headline}"
      context_builder << "THREAT LEVEL: #{article.ai_analysis.threat_level}"
      context_builder << "TRUST SCORE: #{article.ai_analysis.trust_score}"
      context_builder << "VERIFIED SUMMARY: #{article.ai_analysis.summary}"
      context_builder << "---"
    end
    context_text = context_builder.join("\n")

    # 6. Prepend conversation history
    history_block = history.any? ? history.map { |t|
      label = t[:role] == "user" ? "ANALYST QUERY" : "VERITAS RESPONSE"
      "#{label}: #{t[:content]}"
    }.join("\n\n") + "\n---\n" : ""

    system_prompt = <<~PROMPT
      You are the VERITAS RAG Assistant, an elite AI intelligence analyst.
      Your task is to answer the user's query using ONLY the provided INTELLIGENCE CONTEXT.

      RULES:
      1. Synthesize the reports into a cohesive intelligence briefing.
      2. If the context does not contain the answer or is unrelated to the question, state that VERITAS lacks intel on this topic. Do not hallucinate external knowledge.
      3. Cite your sources using brackets like [1] or [3] that match the provided SOURCE numbers.
      4. Keep your response highly professional, analytical, and concise (max 3-4 paragraphs).
      5. Tone: Palantir-esque, objective, military-intelligence style.
      6. You MUST cite every claim with a source number [1]-[5]. Never make uncited statements.
    PROMPT

    user_prompt = <<~PROMPT
      #{history_block}#{context_text}

      CURRENT QUERY: #{user_query}
    PROMPT

    # 7. Build sources metadata
    sources = final_articles.each_with_index.map do |a, i|
      { id: a.id, index: i + 1, headline: a.headline,
        source_name: a.source_name,
        published_at: a.published_at&.strftime("%b %d, %Y"),
        trust_score: a.ai_analysis.trust_score.to_i,
        threat_level: a.ai_analysis.threat_level }
    end

    # 8. Send to Arbiter (Claude Haiku) via OpenRouter
    begin
      response_text = @client.chat(:arbiter, system_prompt, user_prompt, expect_json: false)
      { response: response_text, sources: sources }
    rescue StandardError => e
      Rails.logger.error "[RAG AGENT] Failed: #{e.message}"
      { response: "System Error: Failed to generate intelligence synthesis.", sources: [] }
    end
  end
end
