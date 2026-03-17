# ExtractEntitiesJob
#
# One-shot backfill: runs EntityExtractionService on all articles that have no
# entity mentions yet. Enqueue from console or admin trigger:
#
#   ExtractEntitiesJob.perform_later
#   ExtractEntitiesJob.perform_later(limit: 50)  # process at most 50 articles
#
# The job processes articles in batches to avoid memory bloat.

class ExtractEntitiesJob < ApplicationJob
  queue_as :default

  def perform(limit: nil)
    scope = Article
      .left_joins(:entity_mentions)
      .where(entity_mentions: { id: nil })
      .order(:id)

    scope = scope.limit(limit) if limit.present?

    service    = EntityExtractionService.new
    processed  = 0
    total      = scope.count

    Rails.logger.info "[ExtractEntitiesJob] Starting backfill for #{total} articles"

    scope.find_each do |article|
      result = service.extract(article)
      processed += 1
      Rails.logger.info "[ExtractEntitiesJob] #{processed}/#{total} — Article ##{article.id}: #{result[:mentions_created]} mentions"
    end

    Rails.logger.info "[ExtractEntitiesJob] Backfill complete. Processed #{processed} articles."
  end
end
