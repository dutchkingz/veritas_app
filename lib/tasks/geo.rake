namespace :geo do
  desc "Backfill real coordinates on all articles using GeolocatorService"
  task backfill: :environment do
    total   = Article.count
    updated = 0
    skipped = 0
    failed  = 0

    puts "Backfilling geo coordinates for #{total} articles..."
    puts "Only articles with geo_method 'unresolved' will be updated.\n\n"

    Article.find_each.with_index do |article, idx|
      # Skip articles that already have real coordinates from GeolocatorService
      next if article.geo_method.in?(%w[keyword source_fallback])

      # Build a fake NewsAPI-style hash so GeolocatorService can scan it
      raw = article.raw_data || {}
      item = {
        "title"       => article.headline.to_s,
        "description" => raw["description"].to_s,
        "source"      => { "name" => article.source_name.to_s }
      }

      geo = GeolocatorService.call(item)

      if geo[:geo_method] == "unresolved"
        skipped += 1
        next
      end

      article.update!(
        latitude:   geo[:latitude],
        longitude:  geo[:longitude],
        country:    geo[:country],
        region:     geo[:region],
        geo_method: geo[:geo_method]
      )
      updated += 1

      print "." if (idx % 10).zero?
    rescue StandardError => e
      failed += 1
      Rails.logger.warn "[geo:backfill] Article ##{article.id} failed: #{e.message}"
    end

    puts "\n\nDone!"
    puts "  Updated : #{updated}"
    puts "  Skipped (unresolvable): #{skipped}"
    puts "  Failed  : #{failed}"
    puts "\nRun 'rails geo:backfill' again if you add more articles."
  end
end
