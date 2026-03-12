class EmbeddingService
  def initialize
    @client = OpenRouterClient.new
  end

  def generate(article)
    # Ensure there's enough text to embed
    return false unless article.content.present? || article.ai_analysis&.summary.present?

    Rails.logger.info "[SEMANTIC INTEL] Generating embedding for Article ##{article.id}"

    # We combine the most semantically dense parts of the article
    # This gives the vector the best representation of "what this is about"
    text_to_embed = [
      "HEADLINE: #{article.headline}",
      "TOPIC: #{article.ai_analysis&.geopolitical_topic || 'Unknown'}",
      "SUMMARY: #{article.ai_analysis&.summary}",
      # Add a chunk of the raw content just for extra context
      ActionController::Base.helpers.strip_tags(article.content.to_s)[0..1000]
    ].compact.join("\n\n")

    begin
      vector = @client.embed(text_to_embed)
      
      if vector && vector.length == 1536
        article.update!(embedding: vector)
        Rails.logger.info "[SEMANTIC INTEL] ✅ Vector (1536 dims) saved for Article ##{article.id}"
        true
      else
        Rails.logger.error "[SEMANTIC INTEL] ❌ Invalid vector received: #{vector&.length} dims"
        false
      end
    rescue StandardError => e
      Rails.logger.error "[SEMANTIC INTEL] ❌ Failed to generate embedding: #{e.message}"
      false
    end
  end
end
