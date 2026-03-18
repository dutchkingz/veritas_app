class NarrativeSignatureService
  MATCH_THRESHOLD = 0.18  # cosine distance — tighter than convergence (0.15) to avoid false merges

  def classify(article)
    return unless article.embedding.present?

    # Find closest existing active signature
    match = NarrativeSignature.active
              .nearest_neighbors(:centroid, article.embedding, distance: "cosine")
              .first

    if match && match.neighbor_distance < MATCH_THRESHOLD
      absorb(match, article)
    else
      Rails.logger.info "[SIGNATURE] Article ##{article.id} — no signature match, queued for clustering"
    end
  end

  private

  def absorb(signature, article)
    NarrativeSignatureArticle.find_or_create_by!(
      narrative_signature: signature,
      article: article
    ) do |nsa|
      nsa.cosine_distance = signature.nearest_neighbors(:centroid, article.embedding, distance: "cosine")
                                     .first&.neighbor_distance
      nsa.matched_at = Time.current
    end

    signature.update!(last_seen_at: Time.current)
    signature.recompute_centroid!

    Rails.logger.info "[SIGNATURE] Article ##{article.id} matched '#{signature.label}' " \
                      "(#{signature.match_count} total, distance: #{signature.narrative_signature_articles.find_by(article: article)&.cosine_distance&.round(4)})"
  end
end
