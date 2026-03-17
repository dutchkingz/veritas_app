namespace :veritas do
  namespace :narrative do
    desc "Generate narrative routes from similar articles"
    task generate_routes: :environment do
      puts "🦞 Starting narrative route generation..."
      limit = ENV['LIMIT']&.to_i || 50
      force = ENV['FORCE'] == 'true'
      
      if force
        puts "⚠️  FORCE MODE: Will create routes even for articles with existing arcs"
      end
      
      service = NarrativeRouteGeneratorService.new
      routes_created = service.generate_routes(limit: limit, force: force)
      
      puts "✅ Route generation complete: #{routes_created} routes created"
    end
    
    desc "Delete all routes/arcs and regenerate with current article coordinates"
    task regenerate: :environment do
      arc_count   = NarrativeArc.count
      route_count = NarrativeRoute.count
      puts "Deleting #{route_count} routes and #{arc_count} arcs..."
      NarrativeRoute.delete_all
      NarrativeArc.delete_all
      puts "Regenerating routes for all articles with coordinates..."
      service = NarrativeRouteGeneratorService.new
      routes_created = service.generate_routes(limit: nil, force: true)
      puts "Done! #{routes_created} routes created."
    end

    desc "Show narrative route statistics"
    task stats: :environment do
      puts "\n🦞 VERITAS Narrative Route Statistics\n"
      puts "=" * 50
      
      total_routes = NarrativeRoute.count
      total_arcs = NarrativeArc.count
      total_hops = NarrativeRoute.sum(:total_hops)
      
      puts "Total Routes: #{total_routes}"
      puts "Total Arcs: #{total_arcs}"
      puts "Total Hops: #{total_hops}"
      puts "Avg Hops per Route: #{(total_hops.to_f / [total_routes, 1].max).round(2)}"
      
      puts "\nRoutes by Status:"
      NarrativeRoute.group(:status).count.each do |status, count|
        puts "  #{status}: #{count}"
      end
      
      puts "\nRoutes by Completion:"
      completed = NarrativeRoute.where(is_complete: true).count
      puts "  Complete: #{completed}"
      puts "  Incomplete: #{total_routes - completed}"
      
      puts "\nRecent Routes (last 5):"
      NarrativeRoute.order(created_at: :desc).limit(5).each do |route|
        puts "  - #{route.name} (#{route.total_hops} hops)"
      end
    end
  end
end
