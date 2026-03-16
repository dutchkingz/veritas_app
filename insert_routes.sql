-- Insert a narrative arc if none exists
INSERT INTO narrative_arcs (article_id, origin_country, origin_lat, origin_lng, target_country, target_lat, target_lng, arc_color, created_at, updated_at)
SELECT id, 'Russia', 55.7558, 37.6173, 'United States', 38.9072, -77.0369, '#00f0ff', NOW(), NOW()
FROM articles
WHERE id IS NOT NULL
LIMIT 1
ON CONFLICT DO NOTHING;

-- Get the arc id
WITH arc AS (
  SELECT id FROM narrative_arcs ORDER BY id DESC LIMIT 1
)
-- Insert route 1: RT → Sputnik → Fox Blog
INSERT INTO narrative_routes (narrative_arc_id, name, hops, is_complete, status, description, created_at, updated_at)
SELECT arc.id,
       'Test Route: RT → Sputnik → Fox Blog',
       '[{
          "source_name": "RT",
          "source_country": "Russia",
          "lat": 55.7558,
          "lng": 37.6173,
          "published_at": "2026-03-15T10:00:00Z",
          "framing_shift": "original",
          "confidence_score": 0.9,
          "delay_from_previous": 0
        }, {
          "source_name": "Sputnik",
          "source_country": "Hungary",
          "lat": 47.4979,
          "lng": 19.0402,
          "published_at": "2026-03-15T10:30:00Z",
          "framing_shift": "amplified",
          "confidence_score": 0.8,
          "delay_from_previous": 1800
        }, {
          "source_name": "Fox Blog",
          "source_country": "United States",
          "lat": 40.7128,
          "lng": -74.0060,
          "published_at": "2026-03-15T11:15:00Z",
          "framing_shift": "distorted",
          "confidence_score": 0.7,
          "delay_from_previous": 2700
        }]'::jsonb,
       true,
       'tracking',
       'Test route showing framing shift from original to amplified to distorted.',
       NOW(),
       NOW()
FROM arc;

-- Insert route 2: CNN → BBC
WITH arc AS (
  SELECT id FROM narrative_arcs ORDER BY id DESC LIMIT 1
)
INSERT INTO narrative_routes (narrative_arc_id, name, hops, is_complete, status, description, created_at, updated_at)
SELECT arc.id,
       'Two-Hop Test: CNN → BBC',
       '[{
          "source_name": "CNN",
          "source_country": "United States",
          "lat": 33.7490,
          "lng": -84.3880,
          "published_at": "2026-03-15T12:00:00Z",
          "framing_shift": "original",
          "confidence_score": 0.85,
          "delay_from_previous": 0
        }, {
          "source_name": "BBC",
          "source_country": "United Kingdom",
          "lat": 51.5074,
          "lng": -0.1278,
          "published_at": "2026-03-15T13:00:00Z",
          "framing_shift": "neutralized",
          "confidence_score": 0.75,
          "delay_from_previous": 3600
        }]'::jsonb,
       true,
       'tracking',
       'Simple two-hop test route.',
       NOW(),
       NOW()
FROM arc;

SELECT 'Inserted routes' AS result;