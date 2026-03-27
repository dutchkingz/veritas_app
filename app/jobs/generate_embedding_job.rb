class GenerateEmbeddingJob < ApplicationJob
  queue_as :default
  
  # Generate embedding for a single article
  def perform(article_id)
    article = Article.find_by(id: article_id)
    return unless article
    return if article.embedding.present?  # Already has embedding

    # Use .presence so empty strings ("") fall through to nil correctly.
    # Without this, content: "" would be non-nil but useless, skipping the
    # summary fallback and sending garbage text to the embedding API.
    unless article.content.presence || article.ai_analysis&.summary.presence
      Rails.logger.warn "[GenerateEmbeddingJob] Article ##{article_id} has no content or summary — skipping"
      return
    end
    
    service = EmbeddingService.new
    if service.generate(article)
      Rails.logger.info "[GenerateEmbeddingJob] ✅ Embedding generated for Article ##{article_id}"
    else
      Rails.logger.warn "[GenerateEmbeddingJob] ⚠️ Failed to generate embedding for Article ##{article_id}"
    end
  end
  
  # Generate embeddings for multiple articles (batch)
  def self.generate_for_articles(article_ids)
    article_ids.each do |article_id|
      perform_later(article_id)
    end
  end
  
  # Generate embeddings for all articles without them
  def self.generate_all_missing
    article_ids = Article.where(embedding: nil)
                         .where.not(content: nil)
                         .pluck(:id)
    
    Rails.logger.info "[GenerateEmbeddingJob] Queueing #{article_ids.count} articles for embedding generation"
    generate_for_articles(article_ids)
  end
end