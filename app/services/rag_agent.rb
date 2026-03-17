class RagAgent
  # MMR: 70% relevance, 30% diversity — tunable
  MMR_LAMBDA = 0.7
  MMR_K      = 5   # final articles fed to the LLM

  def initialize(user: nil)
    @client = OpenRouterClient.new(user: user)
    @voice_mode = false
  end

  # voice_briefing: true returns a short 2-sentence spoken summary (no citations)
  def ask(user_query, history: [], perspective_id: nil, voice_briefing: false)
    @voice_mode = voice_briefing
    # Load perspective lens — boosts matching sources in MMR relevance scoring
    @perspective = perspective_id.present? ? PerspectiveFilter.find_by(id: perspective_id) : nil

    # Route temporal queries to a dedicated timeline analysis path
    return temporal_ask(user_query, history: history) if temporal_query?(user_query)

    # 1. Query decomposition — complex queries become 2-3 focused sub-queries
    sub_queries = decompose_query(user_query)

    # 2. Embed all sub-queries; first is the primary relevance anchor
    query_vectors = sub_queries.filter_map { |q| @client.embed(q) }
    return error_response("Error: Could not generate semantic vector.") if query_vectors.empty?

    primary_vector = query_vectors.first

    # 3. Base article scope — all filters at DB level
    base_scope = Article
      .joins(:ai_analysis)
      .where.not(embedding: nil)
      .where.not(published_at: nil)
      .where.not(ai_analyses: { summary: [nil, ''] })
      .where(ai_analyses: { analysis_status: 'complete' })
      .includes(:ai_analysis, :country)

    # 4. Vector search — 15 candidates per sub-query, merged and deduplicated
    vector_candidates = query_vectors.flat_map do |vec|
      base_scope.nearest_neighbors(:embedding, vec, distance: "cosine").limit(15).to_a
    end.uniq(&:id)

    # 5. Hybrid: full-text search catches exact proper nouns the vector misses
    ft_candidates = fulltext_search(user_query, base_scope)

    # 5b. Entity-centric: targeted search for named entities (persons, orgs, places)
    entity_candidates = entity_search(user_query, base_scope)

    all_candidates = (vector_candidates + ft_candidates + entity_candidates).uniq(&:id)
    return error_response("No relevant intelligence found.") if all_candidates.empty?

    # 6. MMR selection — balances relevance (composite score) and inter-article diversity
    final_articles = mmr_select(all_candidates, primary_vector)
    return error_response("No relevant intelligence found.") if final_articles.empty?

    # 7. Build prompt
    context_text   = build_context(final_articles)
    history_block  = build_history_block(history)
    user_prompt    = "#{history_block}#{context_text}\n\nCURRENT QUERY: #{user_query}"

    sources = build_sources(final_articles)

    # 8. Send to Arbiter and extract confidence calibration from first line
    begin
      raw = @client.chat(:arbiter, build_system_prompt, user_prompt, expect_json: false)
      response_text, confidence = extract_confidence(raw)
      { response: response_text, sources: sources, confidence: confidence }
    rescue StandardError => e
      Rails.logger.error "[RAG AGENT] Failed: #{e.message}"
      { response: "System Error: Failed to generate intelligence synthesis.", sources: [], confidence: "LOW" }
    end
  end

  private

  # ── Query Decomposition ──────────────────────────────────────────────────────

  def decompose_query(query)
    return [query] unless complex_query?(query)

    system_prompt = <<~SYS
      You are an OSINT query analyst. Decompose this complex intelligence query into 2-3 focused
      sub-queries optimized for semantic vector search. Output ONLY a JSON array of strings.
      Example: ["sub-query one", "sub-query two", "sub-query three"]
    SYS

    raw = @client.chat(:arbiter, system_prompt, query, expect_json: false)
    json_match = raw&.match(/\[.*?\]/m)
    parsed = JSON.parse(json_match.to_s)
    parsed.is_a?(Array) && parsed.all? { |q| q.is_a?(String) } ? [query] + parsed.first(2) : [query]
  rescue StandardError
    [query]
  end

  def complex_query?(query)
    query.split.size > 8 ||
      query.match?(/\b(and|between|link|connection|relation|compare|versus|vs\.?)\b/i)
  end

  # ── Hybrid Full-Text Search ──────────────────────────────────────────────────

  def fulltext_search(query, scope)
    scope.where(
      "to_tsvector('english', COALESCE(articles.headline, '') || ' ' || COALESCE(articles.content, '')) " \
      "@@ plainto_tsquery('english', ?)",
      query
    ).limit(10).to_a
  rescue StandardError => e
    Rails.logger.warn "[RAG] Full-text search failed: #{e.message}"
    []
  end

  # ── Entity-Centric Search ────────────────────────────────────────────────────

  ENTITY_MIN_LENGTH = 3
  STOPWORDS = %w[the a an in on at of for to with from by how has what when where
                 who which is are was were been will be have had do does did should
                 would could can may might must show tell find give about over across
                 between among compared versus vs and or not but than its their our
                 your his her their those these that this changes changed change
                 last past over time weeks months years].freeze

  # Extract potential named entities: sequences of capitalized words not in stopwords
  def extract_entities(query)
    tokens = query.scan(/\b[A-Z][a-zA-Z]{#{ENTITY_MIN_LENGTH - 1},}\b/)
    tokens.reject { |t| STOPWORDS.include?(t.downcase) }.uniq
  end

  # Run targeted DB searches for each detected entity — finds articles that explicitly mention them
  def entity_search(query, scope)
    entities = extract_entities(query)
    return [] if entities.empty?

    results = entities.flat_map do |entity|
      scope.where(
        "to_tsvector('english', COALESCE(articles.headline, '') || ' ' || COALESCE(articles.content, '')) " \
        "@@ phraseto_tsquery('english', ?)",
        entity
      ).limit(5).to_a
    rescue StandardError
      []
    end

    results.uniq(&:id)
  rescue StandardError => e
    Rails.logger.warn "[RAG] Entity search failed: #{e.message}"
    []
  end

  # ── MMR Selection ────────────────────────────────────────────────────────────

  def mmr_select(candidates, query_vector)
    selected  = []
    remaining = candidates.dup

    MMR_K.times do
      break if remaining.empty?

      best = remaining.max_by do |article|
        rel        = relevance_score(article, query_vector)
        redundancy = selected.empty? ? 0.0 : selected.map { |s| cosine_sim(article.embedding, s.embedding) }.max
        MMR_LAMBDA * rel - (1 - MMR_LAMBDA) * redundancy
      end

      selected  << best
      remaining.delete(best)
    end

    selected
  end

  # Composite relevance: cosine similarity weighted by trust, recency, threat, and perspective
  def relevance_score(article, query_vector)
    a        = article.ai_analysis
    cosine   = cosine_sim(article.embedding, query_vector)
    trust    = 0.5 + (a.trust_score.to_f.clamp(0, 100) / 200.0)  # → 0.5–1.0
    recency  = article.published_at >= 7.days.ago  ? 1.20 :
               article.published_at >= 30.days.ago ? 1.10 : 1.0
    threat   = { 'CRITICAL' => 1.15, 'HIGH' => 1.10, 'MODERATE' => 1.05 }
                 .fetch(a.threat_level, 1.0)
    # Perspective lens: 1.5× boost for sources matching the active perspective
    lens     = @perspective&.matches_source?(article.source_name) ? 1.5 : 1.0
    cosine * trust * recency * threat * lens
  end

  def cosine_sim(vec_a, vec_b)
    a = Array(vec_a)
    b = Array(vec_b)
    return 0.0 unless a.size == b.size && a.size.positive?
    dot    = a.zip(b).sum { |x, y| x * y }
    norm_a = Math.sqrt(a.sum { |x| x**2 })
    norm_b = Math.sqrt(b.sum { |x| x**2 })
    return 0.0 if norm_a.zero? || norm_b.zero?
    (dot / (norm_a * norm_b)).clamp(-1.0, 1.0)
  end

  # ── Prompt & Context Building ────────────────────────────────────────────────

  def build_context(articles)
    lines = ["AVAILABLE INTELLIGENCE CONTEXT:"]
    articles.each_with_index do |article, i|
      lines << "---"
      lines << "SOURCE [#{i + 1}]: #{article.source_name} (#{article.country&.iso_code || 'GLOBAL'})"
      lines << "HEADLINE: #{article.headline}"
      lines << "THREAT LEVEL: #{article.ai_analysis.threat_level}"
      lines << "TRUST SCORE: #{article.ai_analysis.trust_score}"
      lines << "VERIFIED SUMMARY: #{article.ai_analysis.summary}"
      lines << "---"
    end
    lines.join("\n")
  end

  def build_history_block(history)
    return "" unless history.any?
    history.map { |t|
      label = t[:role] == "user" ? "ANALYST QUERY" : "VERITAS RESPONSE"
      "#{label}: #{t[:content]}"
    }.join("\n\n") + "\n---\n"
  end

  def build_system_prompt
    return build_voice_system_prompt if @voice_mode

    perspective_note = @perspective ? "\nACTIVE PERSPECTIVE LENS: #{@perspective.name.upcase} — sources from this perspective have been prioritised in the context. Frame your synthesis from this viewpoint while noting where other perspectives diverge." : ""
    <<~PROMPT
      You are the VERITAS RAG Assistant, an elite AI intelligence analyst.
      Answer the user's query using ONLY the provided INTELLIGENCE CONTEXT.#{perspective_note}

      RULES:
      1. Synthesize the reports into a cohesive intelligence briefing.
      2. If the context is unrelated or insufficient, state that VERITAS lacks intel on this topic. Never hallucinate.
      3. Cite EVERY claim with a source number [1]-[5]. Never write an uncited sentence.
      4. Keep your response professional, analytical, and concise (max 3-4 paragraphs).
      5. Tone: Palantir-esque, objective, military-intelligence style.
      6. CONFIDENCE CALIBRATION — the ABSOLUTE FIRST LINE of your response must be exactly one of:
           CONFIDENCE: HIGH    (4-5 directly relevant, high-trust sources)
           CONFIDENCE: MEDIUM  (2-3 sources partially address the question)
           CONFIDENCE: LOW     (sources are tangential or database coverage is thin)
         Then one blank line, then your response.
    PROMPT
  end

  def build_voice_system_prompt
    <<~PROMPT
      You are VERITAS, an AI intelligence system delivering a spoken briefing.
      Answer the query in exactly 2 sentences. No citations. No confidence prefix.
      Be direct, authoritative, and informative. Military-intelligence tone.
      Use only information from the provided context. If context is insufficient, say so in one sentence.
    PROMPT
  end

  # ── Response Parsing ─────────────────────────────────────────────────────────

  def extract_confidence(raw)
    if (m = raw&.match(/\ACONFIDENCE:\s*(HIGH|MEDIUM|LOW)\s*\n/i))
      confidence    = m[1].upcase
      response_text = raw.sub(/\ACONFIDENCE:\s*(HIGH|MEDIUM|LOW)\s*\n+/i, '').strip
    else
      confidence    = 'MEDIUM'
      response_text = raw.to_s.strip
    end
    [response_text, confidence]
  end

  def build_sources(articles)
    articles.each_with_index.map do |a, i|
      { id:           a.id,
        index:        i + 1,
        headline:     a.headline,
        source_name:  a.source_name,
        published_at: a.published_at&.strftime("%b %d, %Y"),
        trust_score:  a.ai_analysis.trust_score.to_i,
        threat_level: a.ai_analysis.threat_level }
    end
  end

  def error_response(msg)
    { response: msg, sources: [], confidence: "LOW" }
  end

  # ── Timeline RAG ─────────────────────────────────────────────────────────────

  TEMPORAL_PATTERN = /\b(how has|changed|evolution|trend|over time|over the (last|past)|
                         timeline|history|shifted|narrative drift|weeks?|months?)\b/ix.freeze

  def temporal_query?(query)
    query.match?(TEMPORAL_PATTERN)
  end

  def temporal_ask(user_query, history: [])
    vector = @client.embed(user_query)
    return error_response("Error: Could not generate semantic vector.") unless vector

    # Broader window (30 days) and looser similarity for temporal analysis
    candidates = Article
      .joins(:ai_analysis)
      .where.not(embedding: nil)
      .where(published_at: 30.days.ago..Time.current)
      .where(ai_analyses: { analysis_status: 'complete' })
      .where.not(ai_analyses: { summary: [nil, ''] })
      .includes(:ai_analysis, :country)
      .nearest_neighbors(:embedding, vector, distance: "cosine")
      .limit(60)
      .to_a
      .select { |a| a.neighbor_distance < 0.35 }

    return error_response("Insufficient data to trace narrative evolution.") if candidates.size < 3

    # Bucket into 4 weekly windows (most recent first in display, earliest first chronologically)
    buckets = (0..3).filter_map do |i|
      window_start = (i + 1).weeks.ago
      window_end   = i.weeks.ago
      arts = candidates.select { |a| a.published_at >= window_start && a.published_at < window_end }
                       .sort_by { |a| -a.ai_analysis.trust_score.to_f }
      arts.any? ? { label: week_label(i), articles: arts } : nil
    end.reverse  # chronological order for the prompt

    return error_response("Insufficient temporal data — fewer than 2 weekly buckets found.") if buckets.size < 2

    context_lines = ["TEMPORAL INTELLIGENCE CONTEXT (chronological narrative evolution):"]
    buckets.each_with_index do |bucket, bi|
      context_lines << "\n━━ #{bucket[:label].upcase} ━━"
      bucket[:articles].first(3).each_with_index do |a, i|
        context_lines << "[#{bi + 1}.#{i + 1}] #{a.source_name} (#{a.country&.iso_code || '??'}): #{a.headline}"
        context_lines << "    #{a.ai_analysis.summary}"
      end
    end

    temporal_system_prompt = <<~PROMPT
      You are the VERITAS Temporal Intelligence Analyst.
      Analyze how this narrative has evolved over time using the provided chronological context.

      RULES:
      1. Describe the narrative ARC — how framing, emphasis, or tone shifted week by week.
      2. Identify inflection points — moments where the narrative changed significantly.
      3. Note which outlets drove shifts vs. which amplified existing narratives.
      4. Cite sources as [week.article] e.g. [1.1], [2.3].
      5. Tone: analytical, intelligence-grade. Max 4 paragraphs.
      6. ABSOLUTE FIRST LINE must be: CONFIDENCE: HIGH, CONFIDENCE: MEDIUM, or CONFIDENCE: LOW
    PROMPT

    history_block = build_history_block(history)
    user_prompt   = "#{history_block}#{context_lines.join("\n")}\n\nTEMPORAL QUERY: #{user_query}"
    sources       = build_sources(buckets.flat_map { |b| b[:articles].first(2) }.uniq(&:id))

    begin
      raw = @client.chat(:arbiter, temporal_system_prompt, user_prompt, expect_json: false)
      response_text, confidence = extract_confidence(raw)
      { response: response_text, sources: sources, confidence: confidence }
    rescue StandardError => e
      Rails.logger.error "[RAG TEMPORAL] Failed: #{e.message}"
      error_response("System Error: Failed to generate temporal analysis.")
    end
  end

  def week_label(weeks_ago)
    if weeks_ago.zero?
      end_str   = Time.current.strftime("%b %d")
      start_str = 1.week.ago.strftime("%b %d")
      "#{start_str} – #{end_str} (current)"
    else
      start_str = (weeks_ago + 1).weeks.ago.strftime("%b %d")
      end_str   = weeks_ago.weeks.ago.strftime("%b %d")
      "#{start_str} – #{end_str}"
    end
  end
end
