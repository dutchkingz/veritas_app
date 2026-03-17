# FreshIntelligenceJob
# Runs asynchronously after a user search to fetch, geolocate, embed, and
# connect new articles. Broadcasts completion so the frontend can react.
#
# The user already received cached results instantly — this job enriches the
# DB and the globe in the background without blocking the response.

class FreshIntelligenceJob < ApplicationJob
  queue_as :default

  def perform(query:, user_id: nil)
    Rails.logger.info "[FreshIntelligenceJob] Starting fetch for query: '#{query}'"

    # 1. Fetch from NewsAPI
    new_attrs = NewsApiService.new.fetch_by_query(query, max_results: 20)

    if new_attrs.empty?
      Rails.logger.info "[FreshIntelligenceJob] No new articles returned for '#{query}'"
      broadcast_completion(query, 0)
      return
    end

    Rails.logger.info "[FreshIntelligenceJob] Got #{new_attrs.size} new article candidates"

    # 2. Save articles individually — skip failures without aborting the batch
    saved_articles = []
    new_attrs.each do |attrs|
      article = Article.create!(attrs)
      saved_articles << article
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.warn "[FreshIntelligenceJob] Skipping article '#{attrs[:source_url]}': #{e.message}"
    rescue StandardError => e
      Rails.logger.warn "[FreshIntelligenceJob] Unexpected error saving article: #{e.message}"
    end

    Rails.logger.info "[FreshIntelligenceJob] Saved #{saved_articles.size} articles"

    # 3. Generate embeddings for each saved article
    # Globe broadcast happens automatically via after_create_commit :broadcast_to_globe
    # Embeddings are required before route generation
    embedding_service = EmbeddingService.new
    embedded_articles = []

    saved_articles.each do |article|
      success = embedding_service.generate(article)
      embedded_articles << article.reload if success
    rescue StandardError => e
      Rails.logger.warn "[FreshIntelligenceJob] Embedding failed for ##{article.id}: #{e.message}"
    end

    Rails.logger.info "[FreshIntelligenceJob] Embedded #{embedded_articles.size}/#{saved_articles.size} articles"

    # 4. Generate narrative routes — targeted per-article, not full O(n²) sweep
    # Each new article is connected only against its nearest existing neighbors
    route_service = NarrativeRouteGeneratorService.new
    routes_created = 0

    embedded_articles.each do |article|
      routes_created += route_service.generate_routes_for_article(article)
    rescue StandardError => e
      Rails.logger.warn "[FreshIntelligenceJob] Route generation failed for ##{article.id}: #{e.message}"
    end

    Rails.logger.info "[FreshIntelligenceJob] Created #{routes_created} narrative routes"

    # 5. Broadcast route update to globe if any routes were created
    if routes_created > 0
      ActionCable.server.broadcast("globe_channel", {
        type: "routes_updated",
        count: routes_created
      })
    end

    broadcast_completion(query, saved_articles.size)
  rescue StandardError => e
    Rails.logger.error "[FreshIntelligenceJob] Job failed for '#{query}': #{e.class} #{e.message}"
    broadcast_completion(query, 0, error: e.message)
  end

  private

  def broadcast_completion(query, count, error: nil)
    ActionCable.server.broadcast("intelligence_search_#{query.parameterize}", {
      type: "fresh_results_ready",
      query: query,
      new_articles_count: count,
      error: error
    })
  end
end
