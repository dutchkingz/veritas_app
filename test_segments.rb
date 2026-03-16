#!/usr/bin/env ruby
require 'json'
require 'time'

# Simulate the segment_color method from NarrativeRoute
def segment_color(framing_shift)
  case framing_shift
  when 'original'
    '#22c55e' # green
  when 'amplified'
    '#f59e0b' # yellow
  when 'distorted'
    '#ef4444' # red
  when 'neutralized'
    '#3b82f6' # blue
  else
    '#6b7280' # gray
  end
end

# Connect to DB and fetch routes
require 'pg'
config = YAML.load_file('config/database.yml', aliases: true)['development']
conn = PG.connect(
  dbname: config['database'],
  host: config['host'] || 'localhost',
  port: config['port'] || 5432,
  user: config['username'],
  password: config['password']
)

routes = conn.exec("
  SELECT nr.*, a.id as article_id, a.headline, a.source_name, 
         na.origin_country, na.target_country
  FROM narrative_routes nr
  JOIN narrative_arcs na ON nr.narrative_arc_id = na.id
  LEFT JOIN articles a ON na.article_id = a.id
  WHERE nr.hops IS NOT NULL AND jsonb_array_length(nr.hops) > 0
  ORDER BY nr.created_at DESC
  LIMIT 10
")

segments = []

routes.each do |route|
  hops = JSON.parse(route['hops'])
  
  hops.each_with_index do |hop, index|
    next_hop = hops[index + 1]
    next unless next_hop
    
    segments << {
      startLat: hop['lat'].to_f,
      startLng: hop['lng'].to_f,
      endLat: next_hop['lat'].to_f,
      endLng: next_hop['lng'].to_f,
      color: segment_color(hop['framing_shift']),
      sourceName: hop['source_name'],
      targetSourceName: next_hop['source_name'],
      delaySeconds: hop['delay_from_previous'] || 0,
      publishedAt: hop['published_at'],
      confidenceScore: hop['confidence_score'] || 0.5,
      segmentIndex: index,
      totalSegments: hops.length - 1,
      routeId: route['id'].to_i,
      routeName: route['name'],
      arcId: route['narrative_arc_id'].to_i,
      manipulationScore: route['manipulation_score'].to_f,
      amplificationScore: route['amplification_score'].to_f,
      totalHops: route['total_hops'].to_i,
      isComplete: route['is_complete'] == 't',
      articleId: route['article_id']&.to_i,
      headline: route['headline'],
      source: route['source_name'],
      originCountry: route['origin_country'],
      targetCountry: route['target_country']
    }
  end
end

conn.close

# Simulate the full globe_data response
response = {
  points: [],
  arcs: segments.first(200), # limit for performance
  regions: []
}

puts JSON.pretty_generate(response)

# Also output summary
puts "\n=== SUMMARY ==="
puts "Total segments generated: #{segments.count}"
puts "First segment:"
puts "  #{segments.first[:sourceName]} → #{segments.first[:targetSourceName]}"
puts "  Color: #{segments.first[:color]} (framing: #{segments.first[:sourceName] == 'RT' ? 'original' : '?'})"
puts "  Coordinates: #{segments.first[:startLat]}, #{segments.first[:startLng]} → #{segments.first[:endLat]}, #{segments.first[:endLng]}"
puts "\nSegment colors per framing shift:"
segments.each do |s|
  puts "  #{s[:sourceName]} → #{s[:targetSourceName]}: #{s[:color]}"
end