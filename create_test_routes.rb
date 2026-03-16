#!/usr/bin/env ruby
require 'bundler/setup'
require 'active_record'
require './config/environment'

puts "Creating test narrative routes..."

# Find any existing article
article = Article.first
unless article
  puts "No articles found! Exiting."
  exit 1
end

# Find or create a narrative arc for this article
arc = NarrativeArc.find_or_create_by!(
  article_id: article.id,
  origin_country: 'Russia',
  origin_lat: 55.7558,
  origin_lng: 37.6173,
  target_country: 'United States',
  target_lat: 38.9072,
  target_lng: -77.0369,
  arc_color: '#00f0ff'
)

puts "Using Article ID: #{article.id}, Arc ID: #{arc.id}"

# Route 1: RT (Moscow) → Sputnik (Budapest) → Fox Blog (New York)
# framing: original → amplified → distorted
route1 = NarrativeRoute.create!(
  narrative_arc_id: arc.id,
  name: "Test Route: RT → Sputnik → Fox Blog",
  hops: [
    {
      "source_name" => "RT",
      "source_country" => "Russia",
      "lat" => 55.7558,
      "lng" => 37.6173,
      "published_at" => "2026-03-15T10:00:00Z",
      "framing_shift" => "original",
      "confidence_score" => 0.9,
      "delay_from_previous" => 0
    },
    {
      "source_name" => "Sputnik",
      "source_country" => "Hungary",
      "lat" => 47.4979,
      "lng" => 19.0402,
      "published_at" => "2026-03-15T10:30:00Z",
      "framing_shift" => "amplified",
      "confidence_score" => 0.8,
      "delay_from_previous" => 1800  # 30 minutes in seconds
    },
    {
      "source_name" => "Fox Blog",
      "source_country" => "United States",
      "lat" => 40.7128,
      "lng" => -74.0060,
      "published_at" => "2026-03-15T11:15:00Z",
      "framing_shift" => "distorted",
      "confidence_score" => 0.7,
      "delay_from_previous" => 2700  # 45 minutes
    }
  ],
  is_complete: true,
  status: "tracking",
  description: "Test route showing framing shift from original to amplified to distorted."
)

# Route 2: Simple two-hop route
route2 = NarrativeRoute.create!(
  narrative_arc_id: arc.id,
  name: "Two-Hop Test: CNN → BBC",
  hops: [
    {
      "source_name" => "CNN",
      "source_country" => "United States",
      "lat" => 33.7490,
      "lng" => -84.3880,
      "published_at" => "2026-03-15T12:00:00Z",
      "framing_shift" => "original",
      "confidence_score" => 0.85,
      "delay_from_previous" => 0
    },
    {
      "source_name" => "BBC",
      "source_country" => "United Kingdom",
      "lat" => 51.5074,
      "lng" => -0.1278,
      "published_at" => "2026-03-15T13:00:00Z",
      "framing_shift" => "neutralized",
      "confidence_score" => 0.75,
      "delay_from_previous" => 3600
    }
  ],
  is_complete: true,
  status: "tracking",
  description: "Simple two-hop test route."
)

puts "Created narrative routes: #{route1.id}, #{route2.id}"
puts "Total narrative routes: #{NarrativeRoute.count}"