#!/bin/bash
PSQL="/opt/homebrew/Cellar/postgresql@15/15.17/bin/psql -d veritas_app_development -tA"

# Query routes with hops
$PSQL <<EOF
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
    na.target_country
  FROM narrative_routes nr
  JOIN narrative_arcs na ON nr.narrative_arc_id = na.id
  LEFT JOIN articles a ON na.article_id = a.id
  WHERE nr.hops IS NOT NULL AND jsonb_array_length(nr.hops) > 0
  ORDER BY nr.created_at DESC
  LIMIT 10
) t;
EOF