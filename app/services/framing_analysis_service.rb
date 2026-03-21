class FramingAnalysisService
  SYSTEM_PROMPT = <<~PROMPT.freeze
    You are a media framing analyst for the VERITAS intelligence platform.
    You compare two news articles about the same event or topic and classify
    how the TARGET article frames the story relative to the ORIGIN article.

    Framing categories:
    - "original"    — Same framing, same emphasis, balanced reporting with no notable spin
    - "amplified"   — Same core narrative but with heightened emotional language,
                      selective emphasis, exaggerated claims, or expanded reach
    - "distorted"   — Key facts changed, context removed, misleading framing,
                      contradictory spin, or disinformation indicators
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
  rescue StandardError => e
    Rails.logger.warn "[FramingAnalysis] LLM call failed for articles ##{origin.id}→##{target.id}: #{e.message}"
    heuristic_fallback(origin, target)
  end

  private

  def call_llm(origin, target)
    user_prompt = build_prompt(origin, target)
    @client.chat(:arbiter, SYSTEM_PROMPT, user_prompt, expect_json: true)
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
  # Replaces the old hardcoded source-name logic with content-based signals.
  def heuristic_fallback(origin, target)
    jaccard = headline_jaccard(origin.headline, target.headline)

    if jaccard >= 0.6
      { framing: 'original', confidence: 0.6,
        explanation: "Headlines are highly similar (#{(jaccard * 100).round}% word overlap)." }
    elsif jaccard >= 0.3
      { framing: 'amplified', confidence: 0.5,
        explanation: "Headlines share partial overlap (#{(jaccard * 100).round}%); possible selective emphasis." }
    else
      { framing: 'distorted', confidence: 0.45,
        explanation: "Headlines have low overlap (#{(jaccard * 100).round}%); framing may differ significantly." }
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
