#!/usr/bin/env python3
"""Simple API mock that serves globe_data from PostgreSQL"""
import json
import psycopg2
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs

DB_CONFIG = {
    'dbname': 'veritas_app_development',
    'host': 'localhost'
}

def get_segments():
    """Fetch segments from database (mimics build_route_segments)"""
    conn = psycopg2.connect(**DB_CONFIG)
    cur = conn.cursor()
    
    cur.execute("""
        SELECT 
            nr.id, nr.name, nr.hops, nr.manipulation_score, nr.amplification_score,
            nr.total_hops, nr.is_complete, a.id as article_id, a.headline,
            a.source_name, na.origin_country, na.target_country, na.id as arc_id
        FROM narrative_routes nr
        JOIN narrative_arcs na ON nr.narrative_arc_id = na.id
        LEFT JOIN articles a ON na.article_id = a.id
        WHERE nr.hops IS NOT NULL AND jsonb_array_length(nr.hops) > 0
        ORDER BY nr.created_at DESC
        LIMIT 10
    """)
    
    routes = cur.fetchall()
    segments = []
    
    for route in routes:
        (route_id, name, hops_json, manip_score, amp_score, total_hops, 
         is_complete, article_id, headline, source_name, origin_country, 
         target_country, arc_id) = route
        
        hops = hops_json
        for i, hop in enumerate(hops[:-1]):  # skip last hop (no next)
            next_hop = hops[i + 1]
            
            # Determine color based on framing_shift
            framing = hop.get('framing_shift', 'neutral')
            color_map = {
                'original': '#22c55e',
                'amplified': '#f59e0b',
                'distorted': '#ef4444',
                'neutralized': '#3b82f6'
            }
            color = color_map.get(framing, '#6b7280')
            
            segments.append({
                'startLat': hop['lat'],
                'startLng': hop['lng'],
                'endLat': next_hop['lat'],
                'endLng': next_hop['lng'],
                'color': color,
                'sourceName': hop['source_name'],
                'targetSourceName': next_hop['source_name'],
                'delaySeconds': hop.get('delay_from_previous', 0),
                'publishedAt': hop['published_at'],
                'confidenceScore': hop.get('confidence_score', 0.5),
                'segmentIndex': i,
                'totalSegments': len(hops) - 1,
                'routeId': route_id,
                'routeName': name,
                'arcId': arc_id,
                'manipulationScore': float(manip_score) if manip_score else 0.0,
                'amplificationScore': float(amp_score) if amp_score else 0.0,
                'totalHops': int(total_hops) if total_hops else 0,
                'isComplete': is_complete,
                'articleId': article_id,
                'headline': headline,
                'source': source_name,
                'originCountry': origin_country,
                'targetCountry': target_country
            })
    
    cur.close()
    conn.close()
    return segments

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        parsed = urlparse(self.path)
        params = parse_qs(parsed.query)
        
        view = params.get('view', ['arcs'])[0]
        
        if parsed.path == '/api/globe_data':
            segments = get_segments() if view == 'segments' else []
            
            response = {
                'points': [],
                'arcs': segments[:200],  # limit
                'regions': []
            }
            
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Access-Control-Allow-Origin', '*')
            self.end_headers()
            self.wfile.write(json.dumps(response).encode())
            
        elif parsed.path == '/test':
            self.send_response(200)
            self.send_header('Content-Type', 'text/html')
            self.end_headers()
            self.wfile.write(b'<h1>API is running!</h1><p>Test: <a href="/api/globe_data?view=segments">/api/globe_data?view=segments</a></p>')
        else:
            self.send_response(404)
            self.end_headers()
    
    def log_message(self, format, *args):
        print(f"[API] {args[0]}")

if __name__ == '__main__':
    server = HTTPServer(('localhost', 3001), Handler)
    print("🦞 VERITAS Globe API Mock running at http://localhost:3001")
    print("Test: http://localhost:3001/api/globe_data?view=segments")
    server.serve_forever()
