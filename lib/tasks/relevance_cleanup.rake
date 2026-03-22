namespace :veritas do
  desc "Re-filter articles through GeopoliticalRelevanceFilter and delete irrelevant ones"
  task relevance_cleanup: :environment do
    filter = GeopoliticalRelevanceFilter.new
    total = 0
    removed = 0
    errors = 0

    # Process all articles, newest first
    Article.order(created_at: :desc).find_each do |article|
      total += 1

      headline = article.headline.to_s
      description = article.content.to_s.truncate(500).presence ||
                    article.raw_data&.dig("description").to_s.truncate(500)

      # Skip articles with no text to evaluate
      if headline.blank? && description.blank?
        next
      end

      result = filter.call(headline: headline, description: description)

      unless result[:relevant]
        puts "🚫 REMOVING ##{article.id}: #{headline.truncate(80)} [#{result[:method]}]"

        # Destroy dependent records (ai_analysis, narrative_arcs, etc.) via cascade
        article.destroy
        removed += 1
      end
    rescue => e
      errors += 1
      puts "⚠️  Error on Article ##{article.id}: #{e.message}"
    end

    puts
    puts "=== VERITAS Relevance Cleanup ==="
    puts "Total scanned: #{total}"
    puts "Removed:       #{removed}"
    puts "Errors:        #{errors}"
    puts "Remaining:     #{Article.count}"
  end

  desc "Dry-run: show which articles would be removed by relevance_cleanup"
  task relevance_audit: :environment do
    filter = GeopoliticalRelevanceFilter.new
    flagged = 0

    Article.order(created_at: :desc).find_each do |article|
      headline = article.headline.to_s
      description = article.content.to_s.truncate(500).presence ||
                    article.raw_data&.dig("description").to_s.truncate(500)
      next if headline.blank? && description.blank?

      result = filter.call(headline: headline, description: description)

      unless result[:relevant]
        flagged += 1
        puts "🚫 ##{article.id} [#{article.data_source}] #{headline.truncate(90)} — #{result[:method]}"
      end
    rescue => e
      puts "⚠️  Error on Article ##{article.id}: #{e.message}"
    end

    puts
    puts "#{flagged} articles would be removed. Run `rails veritas:relevance_cleanup` to delete them."
  end
end
