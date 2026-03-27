# GeopoliticalRelevanceFilter
# Two-tier filter applied to raw NewsAPI article attributes BEFORE saving to DB.
#
# Tier 1 (free): keyword matching on headline + description.
#   - Strong geopolitical keywords → immediate PASS (skip LLM, save tokens)
#   - Explicit rejection keywords  → immediate REJECT (sports, celebrity, etc.)
#
# Tier 2 (cheap LLM): borderline articles not caught by keywords go to Gemini Flash.
#   - Responds with {"relevant": true/false, "topic": "..."} (~60 tokens)
#   - On LLM failure → falls back to keyword-only result
#
# Usage:
#   result = GeopoliticalRelevanceFilter.call(headline: "...", description: "...")
#   result[:relevant]  # => true / false
#   result[:topic]     # => "Military Conflict", "Trade War", etc.
#   result[:method]    # => "keyword_pass" | "keyword_reject" | "llm" | "llm_fallback"

class GeopoliticalRelevanceFilter
  SYSTEM_PROMPT = <<~PROMPT.freeze
    You are a geopolitical relevance filter for an intelligence platform.
    Respond with ONLY valid JSON — no other text, no markdown fences.
  PROMPT

  # Substrings that strongly indicate geopolitical content — pass without LLM call.
  STRONG_KEYWORDS = %w[
    sanction sanctioned geopolit diplomatic diplomacy diplomat
    military troops warship airstrike missile nuclear warhead
    treaty alliance nato un security council united nations
    sovereignty territorial annexation occupation
    espionage intelligence cia fbi nsa mossad
    disinformation propaganda misinformation
    foreign\ policy embargo trade\ war arms\ deal
    cyber\ attack cyberattack ransomware hacking
    referendum coup insurgency rebellion
    kremlin pentagon whitehouse white\ house
    zelensky zelenskyy putin xi\ jinping
    taiwan\ strait south\ china\ sea
    nato iran israel ukraine russia
    north\ korea dprk hezbollah hamas
    ceasefire offensive counteroffensive
    war\ crimes tribunal icc
  ].freeze

  # Substrings that reliably indicate non-geopolitical noise — reject without LLM call.
  REJECTION_KEYWORDS = %w[
    nfl nba nhl mlb premier\ league bundesliga ligue\ 1 serie\ a
    super\ bowl world\ cup champions\ league
    celebrity gossip kardashian kardashians
    taylor\ swift beyonce drake kanye
    box\ office blockbuster marvel dc\ comics
    grammy oscar bafta emmy
    recipe cooking fashion\ week runway
    cryptocurrency bitcoin ethereum nft
    stock\ market earnings\ report ipo
    horoscope astrology
  ].freeze

  def self.call(headline:, description:)
    new.call(headline: headline, description: description)
  end

  def initialize
    @client = OpenRouterClient.new
  rescue KeyError
    @client = nil
  end

  def call(headline:, description:)
    cache_key = "relevance:#{Digest::SHA256.hexdigest("#{headline}#{description}")[0..15]}"

    Rails.cache.fetch(cache_key, expires_in: 24.hours) do
      text = normalize("#{headline} #{description}")

      # Strong geopolitical keywords FIRST — if the article mentions iran, israel,
      # nato, missiles etc. it passes regardless of any rejection keyword in the
      # description (e.g. "stock market" impact of an airstrike).
      if strong_match?(text)
        topic = infer_topic(text)
        log_decision(:pass, "keyword_pass", headline)
        next build_result(true, topic, :keyword_pass)
      end

      if rejection_match?(text)
        log_decision(:reject, "keyword_reject", headline)
        next build_result(false, "Not geopolitically relevant", :keyword_reject)
      end

      llm_classify(headline, description)
    end
  end

  private

  def rejection_match?(text)
    REJECTION_KEYWORDS.any? { |kw| text.include?(kw) }
  end

  def strong_match?(text)
    STRONG_KEYWORDS.any? { |kw| text.include?(kw) }
  end

  def normalize(str)
    str.to_s.downcase
  end

  def infer_topic(text)
    return "Military Conflict"    if text.match?(/military|troops|airstrike|missile|warship|offensive|ceasefire/)
    return "Nuclear Security"     if text.match?(/nuclear|warhead|nonproliferation/)
    return "Cyber Warfare"        if text.match?(/cyber|ransomware|hacking|malware/)
    return "Diplomatic Relations" if text.match?(/diplomatic|diplomat|treaty|alliance|summit/)
    return "Sanctions & Trade"    if text.match?(/sanction|embargo|trade war|tariff/)
    return "Intelligence & Espionage" if text.match?(/espionage|intelligence|cia|fbi|mossad/)
    return "Disinformation"       if text.match?(/disinformation|propaganda|misinformation/)
    "Geopolitics"
  end

  def llm_classify(headline, description)
    if @client.nil? || VeritasMode.demo?
      # No API client — conservative fallback: pass the article (better to
      # over-include than to silently discard potentially relevant content)
      log_decision(:pass, "llm_fallback_no_client", headline)
      return build_result(true, "Geopolitics (unverified)", :llm_fallback)
    end

    user_prompt = <<~PROMPT
      Is this news article geopolitically relevant?
      (International relations, conflict, diplomacy, security, trade policy, disinformation, military, sanctions count as relevant.)

      Headline: #{headline}
      Description: #{description.to_s.truncate(300)}

      Respond with ONLY this JSON: {"relevant": true, "topic": "brief topic label"}
      or: {"relevant": false, "topic": "not relevant"}
    PROMPT

    raw = @client.chat(:relevance_filter, SYSTEM_PROMPT, user_prompt, expect_json: true)
    relevant = raw["relevant"] == true
    topic    = raw["topic"].to_s.presence || (relevant ? "Geopolitics" : "Not relevant")

    log_decision(relevant ? :pass : :reject, "llm", headline)
    build_result(relevant, topic, :llm)
  rescue OpenRouterClient::RateLimitError => e
    Rails.logger.warn "[GeopoliticalRelevanceFilter] Rate limit hit — passing article as fallback: #{e.message}"
    build_result(true, "Geopolitics (rate-limited fallback)", :llm_fallback)
  rescue StandardError => e
    Rails.logger.warn "[GeopoliticalRelevanceFilter] LLM failed (#{e.class}) — falling back to keyword pass for: #{headline.to_s.truncate(80)}"
    build_result(true, "Geopolitics (llm-fallback)", :llm_fallback)
  end

  def build_result(relevant, topic, method)
    { relevant: relevant, topic: topic, method: method }
  end

  def log_decision(decision, method, headline)
    icon = decision == :pass ? "✅" : "🚫"
    Rails.logger.info "[GeopoliticalFilter] #{icon} #{method.to_s.upcase}: #{headline.to_s.truncate(80)}"
  end
end
