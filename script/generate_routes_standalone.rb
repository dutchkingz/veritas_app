#!/usr/bin/env ruby
# Standalone script to generate embeddings and narrative routes
# Usage: ruby generate_routes_standalone.rb

require 'pg'
require 'net/http'
require 'json'
require 'uri'

# Database connection
DB = PG.connect(dbname: 'veritas_app_development', host: 'localhost')

# OpenRouter API config
OPENROUTER_API_KEY = ENV['OPENROUTER_API_KEY'] || begin
  # Try to read from .env or credentials
  env_file = File.expand_path('../.env', __FILE__)
  if File.exist?(env_file)
    File.read(env_file).lines.find { |l| l.start_with?('OPENROUTER_API_KEY=') }&.split('=')&.last&.strip
  end
end

unless OPENROUTER_API_KEY
  puts "❌ OPENROUTER_API_KEY not set. Please export it or add to .env"
  exit 1
end

def embed_text(text)
  uri = URI('https://openrouter.ai/api/v1/embeddings')
  
  response = Net::HTTP.post_form(uri, {
    'model' => 'text-embedding-3-small',
    'input' => text
  }, {
    'Authorization' => "Bearer #{OPENROUTER_API_KEY}",
    'Content-Type' => 'application/json'
  })
  
  data = JSON.parse(response.body)
  data['data']&.first&.dig('embedding')
rescue => e
  puts "  ⚠️  Embedding failed: #{e.message}"
  nil
end

def haversine_distance(lat1, lng1, lat2, lng2)
  rad_per_deg = Math::PI / 180
  earth_radius_km = 6371
  
  lat1_rad = lat1 * rad_per_deg
  lat2_rad = lat2 * rad_per_deg
  dlat = (lat2 - lat1) * rad_per_deg
  dlng = (lng2 - lng1) * rad_per_deg
  
  a = Math.sin(dlat/2)**2 + Math.cos(lat1_rad) * Math.cos(lat2_rad) * Math.sin(dlng/2)**2
  c = 2 * Math.asin(Math.sqrt(a))
  
  earth_radius_km * c
end

def generate_routes_from_similar_articles
  puts "\n🦞 Starting Narrative Route Generation..."
  puts "=" * 60
  
  # Get articles with embeddings
  articles_with_emb = DB.exec_params("
    SELECT id, headline, source_name, country_id, latitude, longitude, 
           published_at, embedding, ai_analysis->>'geopolitical_topic' as topic
    FROM articles 
    WHERE embedding IS NOT NULL 
      AND latitude IS NOT NULL 
      AND longitude IS NOT NULL
    ORDER BY published_at DESC
    LIMIT 100
  ")
  
  puts "Found #{articles_with_emb.ntuples} articles with embeddings"
  
  if articles_with_emb.ntuples < 2
    puts "⚠️  Need at least 2 articles with embeddings to generate routes"
    return 0
  end
  
  routes_created = 0
  
  articles_with_emb.each do |origin|
    origin_id = origin['id']
    origin_emb = origin['embedding']
    origin_time = origin['published_at']
    
    next unless origin_emb && origin_time
    
    # Find similar articles (simple cosine similarity in Ruby for demo)
    similar = []
    
    articles_with_emb.each do |candidate|
      next if candidate['id'] == origin_id
      
      cand_emb = candidate['embedding']
      cand_time = candidate['published_at']
      
      next unless cand_emb && cand_time
      
      # Time window: within 7 days
      time_diff = (DateTime.parse(cand_time) - DateTime.parse(origin_time)).to_i.abs
      next if time_diff > 7
      
      # Cosine similarity (simplified - assume vectors are normalized)
      dot_product = 0
      origin_emb.zip(cand_emb).each { |a, b| dot_product += a * b }
      
      similarity = dot_product # Assuming normalized vectors
      
      if similarity > 0.75 # Threshold
        similar << {
          article: candidate,
          similarity: similarity
        }
      end
    end
    
    # Sort by time
    similar.sort_by! { |s| s[:article]['published_at'] }
    
    if similar.any?
      puts "\n  ✓ Article ##{origin_id} has #{similar.length} similar articles"
      
      # Build hops
      all_articles = [origin] + similar.map { |s| s[:article] }
      hops = all_articles.map do |art|
        {
          'source_name' => art['source_name'],
          'source_country' => art['country_id'], # Simplified
          'lat' => art['latitude'].to_f,
          'lng' => art['longitude'].to_f,
          'published_at' => art['published_at'],
          'framing_shift' => 'original', # Simplified
          'confidence_score' => 0.8,
          'delay_from_previous' => 0
        }
      end
      
      # Calculate delays
      hops.each_with_index do |hop, i|
        if i > 0
          prev_time = DateTime.parse(hops[i-1]['published_at'])
          curr_time = DateTime.parse(hop['published_at'])
          hop['delay_from_previous'] = ((curr_time - prev_time) * 24 * 60 * 60).to_i
        end
      end
      
      # Create route if we have at least 2 hops
      if hops.length >= 2
        origin_country = hops.first['source_country'] || 'Unknown'
        target_country = hops.last['source_country'] || 'Unknown'
        
        # Insert route
        DB.exec_params("
          INSERT INTO narrative_routes (
            narrative_arc_id, name, hops, is_complete, status, 
            created_at, updated_at
          ) VALUES (
            (SELECT id FROM narrative_arcs WHERE article_id = $1 LIMIT 1),
            $2,
            $3::jsonb,
            true,
            'tracking',
            NOW(),
            NOW()
          )
          ON CONFLICT DO NOTHING
        ", [origin_id, "Route: #{hops.first['source_name']} → #{hops.last['source_name']}", JSON.generate(hops)])
        
        routes_created += 1
        puts "    → Created route with #{hops.length} hops"
      end
    end
  end
  
  puts "\n" + "=" * 60
  puts "✅ Route generation complete: #{routes_created} routes created"
  routes_created
end

# Main execution
if __FILE__ == $PROGRAM_NAME
  if OPENROUTER_API_KEY.include?('sk-or-')
    puts "✅ OpenRouter API key found"
    count = generate_routes_from_similar_articles
    puts "\nFinal count: #{count} routes created"
  else
    puts "❌ Invalid API key format"
    exit 1
  end
end
