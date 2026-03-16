#!/usr/bin/env ruby
require 'json'
require 'time'

# Helper to map framing_shift to color (from NarrativeRoute)
def segment_color(framing_shift)
  case framing_shift.to_s
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

# Read JSON from psql output
psql_cmd = '/opt/homebrew/Cellar/postgresql@15/15.17/bin/psql -d veritas_app_development -tA'
query = <<~SQL
  SELECT json_agg(row_to_json(t))
  FROM (
    SELECT 
      nr.id,
      nr.name,
      nr.hops,
      nr.manipulation_score,
      nr.amplification_score,
      nr.total_hops,
      nr.is_complete,
      a.id as article_id,
      a.headline,
      a.source_name,
      na.origin_country,
      na.target_country,
      na.id as arc_id
    FROM narrative_routes nr
    JOIN narrative_arcs na ON nr.narrative_arc_id = na.id
    LEFT JOIN articles a ON na.article_id = a.id
    WHERE nr.hops IS NOT NULL AND jsonb_array_length(nr.hops) > 0
    ORDER BY nr.created_at DESC
    LIMIT 10
  ) t;
SQL

output = `#{psql_cmd} -c "#{query.gsub('"', '\"')}" 2>&1`
unless $?.success?
  puts "Error running psql: #{output}"
  exit 1
end

routes = JSON.parse(output.strip)

segments = []

routes.each do |route|
  hops = route['hops']
  next unless hops.is_a?(Array) && hops.size > 1
  
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
      arcId: route['arc_id'].to_i,
      manipulationScore: route['manipulation_score'].to_f,
      amplificationScore: route['amplification_score'].to_f,
      totalHops: route['total_hops'].to_i,
      isComplete: route['is_complete'],
      articleId: route['article_id']&.to_i,
      headline: route['headline'],
      source: route['source_name'],
      originCountry: route['origin_country'],
      targetCountry: route['target_country']
    }
  end
end

# Build the full globe_data response
response = {
  points: [],
  arcs: segments.first(200),
  regions: []
}

puts "=== GLOBE DATA JSON (simulated) ==="
puts JSON.pretty_generate(response)

puts "\n=== SEGMENT VISUALIZATION SUMMARY ==="
puts "Total segments: #{segments.count}"
segments.each_with_index do |seg, idx|
  puts "#{idx+1}. #{seg[:sourceName]} → #{seg[:targetSourceName]}"
  puts "   Color: #{seg[:color]} (framing: #{seg[:sourceName] == 'RT' ? 'original' : seg[:sourceName] == 'Sputnik' ? 'amplified' : 'distorted/neutralized'})"
  puts "   Path: #{seg[:startLat].round(2)}, #{seg[:startLng].round(2)} → #{seg[:endLat].round(2)}, #{seg[:endLng].round(2)}"
  puts "   Delay: #{seg[:delaySeconds]}s"
end

puts "\n=== COLOR GRADIENT VISUAL ==="
segments.each do |seg|
  color_name = case seg[:color]
               when '#22c55e' then 'GREEN  (original)'
               when '#f59e0b' then 'YELLOW (amplified)'
               when '#ef4444' then 'RED    (distorted)'
               when '#3b82f6' then 'BLUE   (neutralized)'
               else 'GRAY'
               end
  puts "#{color_name} #{seg[:sourceName]} → #{seg[:targetSourceName]}"
end