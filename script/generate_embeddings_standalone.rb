#!/usr/bin/env ruby
# Standalone script to generate embeddings for articles without them
# Usage: OPENROUTER_API_KEY=sk-... ruby generate_embeddings_standalone.rb

require 'pg'
require 'net/http'
require 'json'
require 'uri'

# Configuration
DATABASE_URL = ENV['DATABASE_URL'] || 'postgresql://localhost/veritas_app_development'
OPENROUTER_API_KEY = ENV['OPENROUTER_API_KEY']

unless OPENROUTER_API_KEY
  puts "❌ OPENROUTER_API_KEY environment variable required"
  puts "   export OPENROUTER_API_KEY=sk-or-..."
  exit 1
end

# Connect to database
puts "🔌 Connecting to database..."
conn = PG.connect(dbname: 'veritas_app_development', host: 'localhost')

# Helper: generate embedding via OpenRouter
def generate_embedding(text, api_key)
  return nil if text.to_s.strip.empty?
  
  uri = URI('https://openrouter.ai/api/v1/embeddings')
  
  headers = {
    'Authorization' => "Bearer #{api_key}",
    'Content-Type' => 'application/json',
    'HTTP-Referer' => 'https://veritas.local',
    'X-Title' => 'VERITAS OSINT'
  }
  
  body = {
    'model' => 'text-embedding-3-small',
    'input' => text[0..8000]  # Limit length
  }.to_json
  
  response = Net::HTTP.post(uri, body, headers)
  
  if response.code == '200'
    data = JSON.parse(response.body)
    embedding = data['data']&.first&.dig('embedding')
    return embedding if embedding&.length == 1536
  else
    puts "  ⚠️  API error #{response.code}: #{response.body[0..200]}"
  end
  
  nil
rescue => e
  puts "  ⚠️  Embedding failed: #{e.message}"
  nil
end

# Get articles without embeddings
puts "📊 Checking articles..."
result = conn.exec_params("
  SELECT COUNT(*) as total, COUNT(*) FILTER (WHERE embedding IS NULL) as missing
  FROM articles
")
total = result[0]['total'].to_i
missing = result[0]['missing'].to_i

puts "📈 Stats:"
puts "  Total articles: #{total}"
puts "  With embeddings: #{total - missing}"
puts "  Without embeddings: #{missing}"

if missing == 0
  puts "✅ All articles already have embeddings!"
  exit 0
end

# Process articles
puts "\n🦞 Starting embedding generation for #{missing} articles..."
puts "=" * 60

# Fetch articles without embeddings (with AI analysis if available)
articles_result = conn.exec_params("
  SELECT 
    a.id, a.headline, a.content, a.source_name, a.published_at,
    aa.geopolitical_topic, aa.summary
  FROM articles a
  LEFT JOIN ai_analyses aa ON aa.article_id = a.id
  WHERE a.embedding IS NULL
    AND (a.content IS NOT NULL OR aa.summary IS NOT NULL)
  ORDER BY a.published_at DESC
  LIMIT 500  -- Safety limit
")

processed = 0
successful = 0
failed = 0

articles_result.each_with_index do |row, index|
  article_id = row['id']
  headline = row['headline']
  
  puts "[#{index + 1}/#{articles_result.ntuples}] Article ##{article_id}: #{headline[0..60]}..."
  
  # Prepare text for embedding
  text_parts = []
  text_parts << "HEADLINE: #{headline}" if headline
  text_parts << "TOPIC: #{row['geopolitical_topic']}" if row['geopolitical_topic']
  text_parts << "SUMMARY: #{row['summary']}" if row['summary']
  
  # Add content snippet (strip HTML)
  if row['content']
    content = row['content'].gsub(/<[^>]*>/, ' ').gsub(/\s+/, ' ').strip
    text_parts << "CONTENT: #{content[0..1000]}"
  end
  
  text_to_embed = text_parts.join("\n\n")
  
  if text_to_embed.strip.empty?
    puts "  ⚠️  No text to embed, skipping"
    failed += 1
    next
  end
  
  # Generate embedding
  embedding = generate_embedding(text_to_embed, OPENROUTER_API_KEY)
  
  if embedding
    # Save to database
    begin
      conn.exec_params("
        UPDATE articles 
        SET embedding = $1::vector(1536)
        WHERE id = $2
      ", [embedding.to_json, article_id])
      
      puts "  ✅ Embedding generated and saved"
      successful += 1
    rescue => e
      puts "  ❌ Database error: #{e.message}"
      failed += 1
    end
  else
    puts "  ❌ Failed to generate embedding"
    failed += 1
  end
  
  processed += 1
  
  # Rate limiting: 2 requests per second max
  sleep 0.5 if (index + 1) % 10 == 0
  
  # Progress update every 20 articles
  if (index + 1) % 20 == 0
    puts "\n📊 Progress: #{index + 1}/#{articles_result.ntuples} articles"
    puts "  ✅ Successful: #{successful}"
    puts "  ❌ Failed: #{failed}"
    puts "-" * 40
  end
end

puts "\n" + "=" * 60
puts "🎯 EMBEDDING GENERATION COMPLETE"
puts "  Processed: #{processed}"
puts "  Successful: #{successful}"
puts "  Failed: #{failed}"

# Final stats
final_result = conn.exec_params("
  SELECT COUNT(*) as with_embeddings FROM articles WHERE embedding IS NOT NULL
")
new_count = final_result[0]['with_embeddings'].to_i
puts "\n📈 New total with embeddings: #{new_count}/#{total} (#{(new_count.to_f / total * 100).round(1)}%)"

conn.close
puts "✅ Database connection closed"