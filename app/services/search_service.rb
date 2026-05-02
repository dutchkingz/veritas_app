# Unified search service — consolidates demo (keyword AND) and live (pgvector) search.
#
# Usage:
#   SearchService.new(query, scope: Article.all, limit: 50).call
#   Returns: ActiveRecord relation or array of articles
#
# Demo mode: splits query into keywords, requires ALL to appear in headline or
# content (AND logic). Prioritizes headline matches.
#
# Live mode: pgvector semantic search with a similarity threshold — won't return
# irrelevant articles just to fill the limit.

class SearchService
  # Maximum cosine distance — articles beyond this are too dissimilar.
  # 0.35 = ~65% minimum cosine similarity.
  MAX_COSINE_DISTANCE = 0.35

  def initialize(query, scope: Article.all, limit: 50)
    @query = query
    @scope = scope
    @limit = limit
  end

  def call
    return @scope.none if @query.blank?

    if VeritasMode.demo?
      keyword_search
    else
      semantic_search_with_fallback
    end
  end

  private

  # Demo mode: AND-match all keywords against headline/content.
  # "war ships" requires both "war" AND "ships" to appear.
  def keyword_search
    keywords = @query.downcase.split(/\s+/).reject { |w| w.length < 2 }
    return @scope.none if keywords.empty?

    where_clauses = []
    where_params = []
    headline_clauses = []
    headline_params = []

    keywords.each do |kw|
      pattern = "%#{ActiveRecord::Base.sanitize_sql_like(kw)}%"
      where_clauses << "(headline ILIKE ? OR content ILIKE ?)"
      where_params.push(pattern, pattern)
      headline_clauses << "headline ILIKE ?"
      headline_params << pattern
    end

    # Prioritize headline matches
    order_sql = ActiveRecord::Base.sanitize_sql_array(
      ["CASE WHEN #{headline_clauses.join(' AND ')} THEN 0 ELSE 1 END ASC, published_at DESC"] + headline_params
    )

    @scope.where(where_clauses.join(" AND "), *where_params)
          .order(Arel.sql(order_sql))
          .limit(@limit)
  end

  def semantic_search_with_fallback
    vector = OpenRouterClient.new.embed(@query)
    if vector.present?
      candidates = Article.nearest_neighbors(:embedding, vector, distance: "cosine")
                          .limit(@limit)

      # Filter by similarity threshold
      similar_ids = candidates.select { |a| a.neighbor_distance <= MAX_COSINE_DISTANCE }.map(&:id)

      if similar_ids.any?
        @scope.where(id: similar_ids)
      else
        keyword_search
      end
    else
      keyword_search
    end
  rescue StandardError => e
    Rails.logger.warn "[SearchService] Semantic search failed: #{e.message}"
    keyword_search
  end
end
