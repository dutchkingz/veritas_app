-- Generate Narrative Routes from articles with same topic
-- Run: psql -d veritas_app_development -f generate_routes_sql.sql

BEGIN;

-- Create routes for articles with matching geopolitical topics
INSERT INTO narrative_routes (
  narrative_arc_id, 
  name, 
  hops, 
  is_complete, 
  status, 
  created_at, 
  updated_at
)
SELECT 
  na.id as narrative_arc_id,
  'Topic Route: ' || COALESCE(a1.ai_analysis->>'geopolitical_topic', 'Unknown') || ' (' || a1.source_name || ' → ' || a2.source_name || ')' as name,
  jsonb_build_array(
    jsonb_build_object(
      'source_name', a1.source_name,
      'source_country', c1.name,
      'lat', a1.latitude,
      'lng', a1.longitude,
      'published_at', a1.published_at,
      'framing_shift', 'original',
      'confidence_score', 0.85,
      'delay_from_previous', 0
    ),
    jsonb_build_object(
      'source_name', a2.source_name,
      'source_country', c2.name,
      'lat', a2.latitude,
      'lng', a2.longitude,
      'published_at', a2.published_at,
      'framing_shift', CASE 
        WHEN a2.source_name ILIKE '%RT%' OR a2.source_name ILIKE '%Sputnik%' THEN 'amplified'
        WHEN a2.source_name ILIKE '%Breitbart%' OR a2.source_name ILIKE '%Daily Wire%' THEN 'amplified'
        WHEN a2.source_name ILIKE '%CNN%' OR a2.source_name ILIKE '%MSNBC%' THEN 'amplified'
        ELSE 'neutralized'
      END,
      'confidence_score', 0.75,
      'delay_from_previous', EXTRACT(EPOCH FROM (a2.published_at - a1.published_at))::integer
    )
  ) as hops,
  true as is_complete,
  'tracking' as status,
  NOW() as created_at,
  NOW() as updated_at
FROM articles a1
JOIN articles a2 ON a2.id > a1.id
JOIN narrative_arcs na ON na.article_id = a1.id
LEFT JOIN countries c1 ON c1.id = a1.country_id
LEFT JOIN countries c2 ON c2.id = a2.country_id
WHERE 
  a1.ai_analysis->>'geopolitical_topic' IS NOT NULL
  AND a2.ai_analysis->>'geopolitical_topic' IS NOT NULL
  AND a1.ai_analysis->>'geopolitical_topic' = a2.ai_analysis->>'geopolitical_topic'
  AND a1.latitude IS NOT NULL
  AND a2.latitude IS NOT NULL
  AND a1.longitude IS NOT NULL
  AND a2.longitude IS NOT NULL
  AND a2.published_at BETWEEN a1.published_at - INTERVAL '7 days' AND a1.published_at + INTERVAL '2 days'
  AND NOT EXISTS (
    SELECT 1 FROM narrative_routes nr 
    WHERE nr.narrative_arc_id = na.id 
    AND nr.name LIKE '%' || a1.source_name || ' → ' || a2.source_name || '%'
  )
LIMIT 50;

-- Update total_hops for all routes
UPDATE narrative_routes 
SET total_hops = jsonb_array_length(hops),
    total_duration_seconds = COALESCE(
      EXTRACT(EPOCH FROM (
        (hops->>-'published_at')::timestamp - (hops->0->>'published_at')::timestamp
      ))::integer,
      0
    ),
    first_hop_at = (hops->0->>'published_at')::timestamp,
    last_hop_at = (hops->-1->>'published_at')::timestamp,
    origin_lat = (hops->0->>'lat')::float,
    origin_lng = (hops->0->>'lng')::float,
    target_lat = (hops->-1->>'lat')::float,
    target_lng = (hops->-1->>'lng')::float,
    origin_country = hops->0->>'source_country',
    target_country = hops->-1->>'source_country'
WHERE hops IS NOT NULL AND jsonb_array_length(hops) > 0;

COMMIT;

-- Show results
SELECT 'Total Routes' as metric, COUNT(*) as value FROM narrative_routes
UNION ALL
SELECT 'Complete', COUNT(*) FROM narrative_routes WHERE is_complete = true
UNION ALL
SELECT 'Total Hops', COALESCE(SUM(total_hops), 0) FROM narrative_routes
UNION ALL
SELECT 'Avg Hops/Route', ROUND(AVG(total_hops)::numeric, 2) FROM narrative_routes
UNION ALL
SELECT 'Routes with 2+ Hops', COUNT(*) FROM narrative_routes WHERE total_hops >= 2;
