class EmbeddingService
  def initialize
    @client = OpenRouterClient.new
  end

  def generate(article)
    # Skip API calls for demo/seed articles — they don't need real embeddings.
    # NOTE: We check the ARTICLE, not VeritasMode.demo?, because VeritasMode is
    # stored in Solid Cache and silently defaults to "demo" if the cache entry is
    # missing or expired. That caused all embedding jobs to short-circuit in 2ms
    # without ever reaching the API — the "poisoned cache key 2335321407805460513"
    # was actually the hash of "veritas_mode", not an embedding result.
    if article.fallback_demo?
      return article.embedding.present?
    end

    # Use .presence so empty strings ("") are treated as nil, not truthy
    headline = article.headline.presence
    summary  = article.ai_analysis&.summary.presence
    topic    = article.ai_analysis&.geopolitical_topic.presence
    content  = article.content.presence

    # Require content or AI summary — headline alone is too thin for a useful
    # embedding (GDELT placeholder headlines like "source — GDELT" are identical
    # across articles and produce poisoned duplicate vectors).
    unless content || summary
      Rails.logger.warn "[SEMANTIC INTEL] Skipping Article ##{article.id} — no content or summary for embedding"
      return false
    end

    text_to_embed = [
      ("HEADLINE: #{headline}" if headline),
      ("TOPIC: #{topic}" if topic),
      ("SUMMARY: #{summary}" if summary),
      (ActionController::Base.helpers.strip_tags(content)[0..1000] if content)
    ].compact.join("\n\n")

    # Final safety net — refuse to embed trivially short text
    if text_to_embed.length < 50
      Rails.logger.warn "[SEMANTIC INTEL] Skipping Article ##{article.id} — text too short for meaningful embedding (#{text_to_embed.length} chars)"
      return false
    end

    Rails.logger.info "[SEMANTIC INTEL] Generating embedding for Article ##{article.id} (#{text_to_embed.length} chars)"

    begin
      vector = @client.embed(text_to_embed)

      if vector.is_a?(Array) && vector.length == 1536
        article.update!(embedding: vector)
        Rails.logger.info "[SEMANTIC INTEL] ✅ Vector (1536 dims) saved for Article ##{article.id}"
        true
      else
        # Do NOT cache this — a nil/short vector is a transient API failure
        Rails.logger.error "[SEMANTIC INTEL] ❌ Invalid vector received (#{vector&.length || 'nil'} dims) — not caching"
        false
      end
    rescue StandardError => e
      # Do NOT cache errors — the next run should retry with a fresh API call
      Rails.logger.error "[SEMANTIC INTEL] ❌ Embedding API error (not cached): #{e.message}"
      false
    end
  end
end
