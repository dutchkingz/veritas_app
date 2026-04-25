class FramingAnalysisService
  # Seconds to sleep after each successful LLM call to avoid bursting the API.
  INTER_CALL_DELAY = 0.5

  SYSTEM_PROMPT = <<~PROMPT.freeze
    You are a media framing analyst for the VERITAS intelligence platform.
    You compare two news articles about the same event or topic and classify
    how the TARGET article frames the story relative to the ORIGIN article.

    Framing categories:
    - "original"    — Same framing, same emphasis, balanced reporting with no notable spin
    - "amplified"   — Same core narrative but with heightened emotional language,
                      selective emphasis, exaggerated claims, or expanded reach
    - "distorted"   — Key facts changed, context removed, misleading framing,
                      contradictory spin, or disinformation indicators.
                      Do NOT classify as 'distorted' simply because the target
                      is shorter, uses a different headline, or omits minor
                      details. 'distorted' MUST involve a factual contradiction
                      or severe manipulative context removal.
    - "neutralized" — Actively corrects, contextualises, or provides a balanced
                      counter-perspective to the origin article

    You MUST respond with valid JSON only, no other text. Use this exact structure:
    {"framing": "amplified|distorted|neutralized|original", "confidence": 0.0-1.0, "explanation": "One sentence explaining why"}
  PROMPT

  def initialize
    @client = OpenRouterClient.new
  rescue KeyError
    # OPENROUTER_API_KEY not set — service will return heuristic fallbacks
    @client = nil
  end

  # Compare two Article objects and return framing classification.
  # Returns a Hash: { framing: String, confidence: Float, explanation: String }
  def analyze(origin, target)
    return { framing: 'original', confidence: 1.0, explanation: 'Same article.' } if origin.id == target.id

    if @client.nil? || VeritasMode.demo?
      return heuristic_fallback(origin, target)
    end

    result = call_llm(origin, target)
    normalize_result(result)
  rescue OpenRouterClient::RateLimitError
    raise # let the job-level retry_on handle it with exponential backoff
  rescue StandardError => e
    Rails.logger.warn "[FramingAnalysis] LLM call failed for articles ##{origin.id}→##{target.id}: #{e.message}"
    heuristic_fallback(origin, target)
  end

  private

  def call_llm(origin, target)
    user_prompt = build_prompt(origin, target)
    result = @client.chat(:arbiter, SYSTEM_PROMPT, user_prompt, expect_json: true)
    sleep(INTER_CALL_DELAY)
    result
  end

  def build_prompt(origin, target)
    origin_summary = (origin.respond_to?(:summary) && origin.summary.presence) ||
                     origin.try(:content)&.truncate(1500) ||
                     "(no summary available)"
    target_summary = (target.respond_to?(:summary) && target.summary.presence) ||
                     target.try(:content)&.truncate(1500) ||
                     "(no summary available)"

    <<~PROMPT
      ORIGIN ARTICLE:
      Headline: #{origin.headline}
      Source: #{origin.source_name}
      Summary: #{origin_summary}

      TARGET ARTICLE:
      Headline: #{target.headline}
      Source: #{target.source_name}
      Summary: #{target_summary}

      Classify the TARGET article's framing relative to the ORIGIN article.
    PROMPT
  end

  # Ensure the LLM response has exactly the shape we expect.
  def normalize_result(raw)
    framing = raw['framing'].to_s.downcase
    framing = 'original' unless %w[original amplified distorted neutralized].include?(framing)

    confidence = raw['confidence'].to_f.clamp(0.0, 1.0)
    explanation = raw['explanation'].to_s.presence || "No explanation provided."

    { framing: framing, confidence: confidence, explanation: explanation }
  end

  # Headline-overlap heuristic — used in demo mode or when no API key is set.
  # Safely defaults to "original" rather than falsely flagging distortion.
  def heuristic_fallback(origin, target)
    jaccard = headline_jaccard(origin.headline, target.headline)

    if jaccard >= 0.6
      { framing: 'original', confidence: 0.6,
        explanation: "Headlines are highly similar (#{(jaccard * 100).round}% word overlap)." }
    elsif jaccard >= 0.3
      { framing: 'original', confidence: 0.4,
        explanation: "Headlines share partial overlap (#{(jaccard * 100).round}%); lacking LLM for deeper analysis." }
    else
      { framing: 'original', confidence: 0.2,
        explanation: "Headlines have low overlap (#{(jaccard * 100).round}%); lacking LLM to classify true shift." }
    end
  end

  def headline_jaccard(a, b)
    stop_words = %w[the a an and or but in on at to of for is are was were be been
                    being have has had do does did will would could should may might
                    shall can with as by from this that these those it its].to_set

    words_a = a.to_s.downcase.scan(/\w+/).reject { |w| stop_words.include?(w) || w.length < 3 }.to_set
    words_b = b.to_s.downcase.scan(/\w+/).reject { |w| stop_words.include?(w) || w.length < 3 }.to_set

    union = (words_a | words_b)
    return 0.0 if union.empty?

    (words_a & words_b).size.to_f / union.size
  end
end
