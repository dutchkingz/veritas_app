class RagAgent
  def initialize
    @client = OpenRouterClient.new
  end

  def ask(user_query)
    # 1. Embed the user's question
    query_vector = @client.embed(user_query)
    
    return "Error: Could not generate semantic vector for query." unless query_vector

    # 2. Find the top 5 most conceptually relevant articles as context
    # We only take articles that have a verified summary from the Triad
    relevant_articles = Article.where.not(embedding: nil)
                               .nearest_neighbors(:embedding, query_vector, distance: "cosine")
                               .includes(:ai_analysis)
                               .limit(5)
                               .select { |a| a.ai_analysis&.summary.present? }

    if relevant_articles.empty?
      return "I could not find any relevant intelligence in the VERITAS database regarding this query."
    end

    # 3. Construct the Context Block
    context_builder = ["AVAILABLE INTELLIGENCE CONTEXT:"]
    relevant_articles.each_with_index do |article, i|
      context_builder << "---"
      context_builder << "SOURCE [#{i+1}]: #{article.source_name} (#{article.country&.iso_code || 'GLOBAL'})"
      context_builder << "HEADLINE: #{article.headline}"
      context_builder << "THREAT LEVEL: #{article.ai_analysis.threat_level}"
      context_builder << "TRUST SCORE: #{article.ai_analysis.trust_score}"
      context_builder << "VERIFIED SUMMARY: #{article.ai_analysis.summary}"
      context_builder << "---"
    end
    
    context_text = context_builder.join("\n")

    # 4. Prompt the Arbiter Model (Claude Haiku) to answer the user's question using the context
    system_prompt = <<~PROMPT
      You are the VERITAS RAG Assistant, an elite AI intelligence analyst.
      Your task is to answer the user's query using ONLY the provided INTELLIGENCE CONTEXT.
      
      RULES:
      1. Synthesize the reports into a cohesive intelligence briefing.
      2. If the context does not contain the answer or is unrelated to the question, state that VERITAS lacks intel on this topic. Do not hallucinate external knowledge.
      3. Cite your sources using brackets like [1] or [3] that match the provided SOURCE numbers.
      4. Keep your response highly professional, analytical, and concise (max 3-4 paragraphs).
      5. Tone: Palantir-esque, objective, military-intelligence style.
    PROMPT

    user_prompt = <<~PROMPT
      #{context_text}
      
      USER QUERY:
      #{user_query}
    PROMPT

    # 5. Send to Claude Haiku via OpenRouter
    begin
      @client.chat("anthropic/claude-3.5-haiku", system_prompt, user_prompt, expect_json: false)
    rescue StandardError => e
      Rails.logger.error "[RAG AGENT] ❌ Failed: #{e.message}"
      "System Error: Failed to generate intelligence synthesis."
    end
  end
end
