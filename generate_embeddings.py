#!/usr/bin/env python3
"""
Generate embeddings for articles without them using OpenRouter API.
Usage: OPENROUTER_API_KEY=sk-... python3 generate_embeddings.py
"""
import os
import sys
import json
import time
import psycopg2
import requests
from typing import List, Optional

# Database connection
DB_CONFIG = {
    'dbname': 'veritas_app_development',
    'host': 'localhost'
}

# OpenRouter API
OPENROUTER_API_KEY = os.environ.get('OPENROUTER_API_KEY')
if not OPENROUTER_API_KEY:
    print("❌ OPENROUTER_API_KEY environment variable required")
    print("   export OPENROUTER_API_KEY=sk-or-...")
    sys.exit(1)

EMBEDDING_MODEL = 'text-embedding-3-small'
EMBEDDING_DIMENSIONS = 1536

def generate_embedding(text: str) -> Optional[List[float]]:
    """Generate embedding via OpenRouter API."""
    if not text or len(text.strip()) < 10:
        print("  ⚠️  Text too short, skipping")
        return None
    
    url = 'https://openrouter.ai/api/v1/embeddings'
    headers = {
        'Authorization': f'Bearer {OPENROUTER_API_KEY}',
        'Content-Type': 'application/json',
        'HTTP-Referer': 'https://veritas.local',
        'X-Title': 'VERITAS OSINT'
    }
    
    payload = {
        'model': EMBEDDING_MODEL,
        'input': text[:8000]  # Limit length
    }
    
    try:
        response = requests.post(url, headers=headers, json=payload, timeout=30)
        if response.status_code == 200:
            data = response.json()
            embedding = data['data'][0]['embedding']
            if len(embedding) == EMBEDDING_DIMENSIONS:
                return embedding
            else:
                print(f"  ⚠️  Wrong dimensions: {len(embedding)} != {EMBEDDING_DIMENSIONS}")
        else:
            print(f"  ⚠️  API error {response.status_code}: {response.text[:200]}")
    except Exception as e:
        print(f"  ⚠️  Request failed: {e}")
    
    return None

def main():
    print("🦞 VERITAS Embedding Generator")
    print("=" * 60)
    
    # Connect to database
    try:
        conn = psycopg2.connect(**DB_CONFIG)
        cur = conn.cursor()
        print("✅ Connected to database")
    except Exception as e:
        print(f"❌ Database connection failed: {e}")
        sys.exit(1)
    
    # Get statistics
    cur.execute("""
        SELECT 
            COUNT(*) as total,
            COUNT(*) FILTER (WHERE embedding IS NOT NULL) as with_embeddings,
            COUNT(*) FILTER (WHERE embedding IS NULL) as without_embeddings
        FROM articles
    """)
    total, with_embeddings, without_embeddings = cur.fetchone()
    
    print(f"📊 Statistics:")
    print(f"  Total articles: {total}")
    print(f"  With embeddings: {with_embeddings}")
    print(f"  Without embeddings: {without_embeddings}")
    
    if without_embeddings == 0:
        print("✅ All articles already have embeddings!")
        conn.close()
        return
    
    # Fetch articles without embeddings
    cur.execute("""
        SELECT 
            a.id, a.headline, a.content, a.source_name, a.published_at,
            aa.geopolitical_topic, aa.summary
        FROM articles a
        LEFT JOIN ai_analyses aa ON aa.article_id = a.id
        WHERE a.embedding IS NULL
          AND (a.content IS NOT NULL OR aa.summary IS NOT NULL)
        ORDER BY a.published_at DESC
        -- LIMIT 10  -- For testing
    """)
    
    articles = cur.fetchall()
    print(f"\n🔄 Processing {len(articles)} articles...")
    
    processed = 0
    successful = 0
    failed = 0
    
    for idx, article in enumerate(articles):
        article_id, headline, content, source_name, published_at, topic, summary = article
        
        print(f"[{idx + 1}/{len(articles)}] Article #{article_id}: {headline[:60]}...")
        
        # Prepare text for embedding
        text_parts = []
        if headline:
            text_parts.append(f"HEADLINE: {headline}")
        if topic:
            text_parts.append(f"TOPIC: {topic}")
        if summary:
            text_parts.append(f"SUMMARY: {summary}")
        if content:
            # Strip HTML tags
            import re
            content_clean = re.sub(r'<[^>]+>', ' ', content)
            content_clean = re.sub(r'\s+', ' ', content_clean).strip()
            text_parts.append(f"CONTENT: {content_clean[:1000]}")
        
        text_to_embed = "\n\n".join(text_parts)
        
        if not text_to_embed or len(text_to_embed.strip()) < 50:
            print("  ⚠️  Not enough text, skipping")
            failed += 1
            processed += 1
            continue
        
        # Generate embedding
        embedding = generate_embedding(text_to_embed)
        
        if embedding:
            # Save to database
            try:
                cur.execute("""
                    UPDATE articles 
                    SET embedding = %s::vector(1536)
                    WHERE id = %s
                """, (json.dumps(embedding), article_id))
                conn.commit()
                print("  ✅ Embedding saved")
                successful += 1
            except Exception as e:
                conn.rollback()
                print(f"  ❌ Database error: {e}")
                failed += 1
        else:
            print("  ❌ Failed to generate embedding")
            failed += 1
        
        processed += 1
        
        # Rate limiting (2 requests per second max)
        if (idx + 1) % 10 == 0:
            time.sleep(0.5)
        
        # Progress update
        if (idx + 1) % 20 == 0:
            print(f"\n📊 Progress: {idx + 1}/{len(articles)}")
            print(f"  ✅ Successful: {successful}")
            print(f"  ❌ Failed: {failed}")
            print("-" * 40)
    
    # Final statistics
    print("\n" + "=" * 60)
    print("🎯 EMBEDDING GENERATION COMPLETE")
    print(f"  Processed: {processed}")
    print(f"  Successful: {successful}")
    print(f"  Failed: {failed}")
    
    cur.execute("SELECT COUNT(*) FROM articles WHERE embedding IS NOT NULL")
    new_count = cur.fetchone()[0]
    print(f"\n📈 New total with embeddings: {new_count}/{total} ({(new_count/total*100):.1f}%)")
    
    conn.close()
    print("✅ Database connection closed")

if __name__ == '__main__':
    main()