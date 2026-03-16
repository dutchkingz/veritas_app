#!/usr/bin/env ruby
require 'pg'
require 'yaml'

# Load database config
config_path = File.expand_path('config/database.yml', __dir__)
config = YAML.load_file(config_path, aliases: true)['development']

puts "Connecting to #{config['database']}..."

conn = PG.connect(
  dbname: config['database'],
  host: config['host'] || 'localhost',
  port: config['port'] || 5432,
  user: config['username'],
  password: config['password']
)

begin
  # Insert arc if none exists
  conn.exec("
    INSERT INTO narrative_arcs (article_id, origin_country, origin_lat, origin_lng, target_country, target_lat, target_lng, arc_color, created_at, updated_at)
    SELECT id, 'Russia', 55.7558, 37.6173, 'United States', 38.9072, -77.0369, '#00f0ff', NOW(), NOW()
    FROM articles
    WHERE id IS NOT NULL
    LIMIT 1
    ON CONFLICT DO NOTHING
  ")

  # Get latest arc id
  arc_result = conn.exec("SELECT id FROM narrative_arcs ORDER BY id DESC LIMIT 1")
  arc_id = arc_result.first['id']

  # Route 1
  hops1 = [
    {
      source_name: 'RT',
      source_country: 'Russia',
      lat: 55.7558,
      lng: 37.6173,
      published_at: '2026-03-15T10:00:00Z',
      framing_shift: 'original',
      confidence_score: 0.9,
      delay_from_previous: 0
    },
    {
      source_name: 'Sputnik',
      source_country: 'Hungary',
      lat: 47.4979,
      lng: 19.0402,
      published_at: '2026-03-15T10:30:00Z',
      framing_shift: 'amplified',
      confidence_score: 0.8,
      delay_from_previous: 1800
    },
    {
      source_name: 'Fox Blog',
      source_country: 'United States',
      lat: 40.7128,
      lng: -74.0060,
      published_at: '2026-03-15T11:15:00Z',
      framing_shift: 'distorted',
      confidence_score: 0.7,
      delay_from_previous: 2700
    }
  ]

  conn.exec_params("
    INSERT INTO narrative_routes (narrative_arc_id, name, hops, is_complete, status, description, created_at, updated_at)
    VALUES ($1, $2, $3, $4, $5, $6, NOW(), NOW())
  ", [arc_id, 'Test Route: RT → Sputnik → Fox Blog', JSON.generate(hops1), true, 'tracking', 'Test route showing framing shift from original to amplified to distorted.'])

  # Route 2
  hops2 = [
    {
      source_name: 'CNN',
      source_country: 'United States',
      lat: 33.7490,
      lng: -84.3880,
      published_at: '2026-03-15T12:00:00Z',
      framing_shift: 'original',
      confidence_score: 0.85,
      delay_from_previous: 0
    },
    {
      source_name: 'BBC',
      source_country: 'United Kingdom',
      lat: 51.5074,
      lng: -0.1278,
      published_at: '2026-03-15T13:00:00Z',
      framing_shift: 'neutralized',
      confidence_score: 0.75,
      delay_from_previous: 3600
    }
  ]

  conn.exec_params("
    INSERT INTO narrative_routes (narrative_arc_id, name, hops, is_complete, status, description, created_at, updated_at)
    VALUES ($1, $2, $3, $4, $5, $6, NOW(), NOW())
  ", [arc_id, 'Two-Hop Test: CNN → BBC', JSON.generate(hops2), true, 'tracking', 'Simple two-hop test route.'])

  puts "Inserted 2 narrative routes for arc #{arc_id}"
rescue PG::Error => e
  puts "Error: #{e.message}"
ensure
  conn&.close
end