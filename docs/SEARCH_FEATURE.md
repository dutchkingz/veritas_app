# VERITAS Search & Discovery

Semantic search interface for intelligence discovery with real-time Globe filtering.

## Features

### 1. Semantic Vector Search
- Uses pgvector for **cosine similarity** search
- Embeds user query into 1536-dim vector (same model as articles)
- Finds conceptually related articles, not just keyword matches

### 2. Trending Topics
- Auto-generated from recent articles (last 7 days)
- Extracted from `ai_analyses.geopolitical_topic`
- Color-coded by topic (Ukraine=blue, Russia=red, etc.)
- Clicking a tag triggers instant search

### 3. Globe Integration
- Search dispatches `veritas:search` event
- Globe controller filters arcs/points based on query
- Automatically flies to first result
- Supports both simple arcs and multi-segment routes

### 4. Real-time Updates
- SearchChannel broadcasts results via ActionCable
- No page reload required (Turbo-powered)
- Loading states and animations

## Architecture

```
┌─────────────────┐
│ Search Page     │
│ - search_controller.js │
│ - Trending Topics      │
│ - Search Form          │
└─────────────────┘
         │
         │ veritas:search event
         ▼
┌─────────────────┐
│ Globe Controller │
│ - Filters arcs/points│
│ - Packet animation   │
│ - Fly-to result      │
└─────────────────┘
         │
         │ API call with search_query
         ▼
┌─────────────────┐
│ PagesController │
│ - Embed query   │
│ - pgvector search│
│ - Returns filtered│
└─────────────────┘
```

## Usage

### Direct URL
```
/search?q=ukraine
/search?q=iran+missiles
/search?q=NATO+deployment
```

### Via Search Form
1. Type query (autocomplete after 3 chars)
2. Press Enter or click SEARCH
3. Globe filters to matching arcs/points
4. Click trending tags for instant search

### Via JavaScript
```javascript
// Trigger search programmatically
window.dispatchEvent(new CustomEvent('veritas:search', {
  detail: { query: 'Ukraine', timestamp: Date.now() }
}))

// Clear search
window.dispatchEvent(new CustomEvent('veritas:searchClear'))
```

## API Endpoints

### GET /api/trending_topics
Returns trending topics from recent articles.

**Response:**
```json
{
  "topics": [
    { "keyword": "Ukraine", "count": 42, "color": "#3b82f6" },
    { "keyword": "Russia", "count": 38, "color": "#ef4444" }
  ],
  "generated_at": "2026-03-15T21:00:00Z"
}
```

### GET /api/search_suggestions?q=...
Autocomplete suggestions (optional feature).

**Response:**
```json
{
  "query": "ukr",
  "suggestions": ["Ukraine", "UKR Defense", "Eastern Ukraine"]
}
```

## Globe Filtering Logic

When a search is performed:

1. Query is embedded via OpenRouter API
2. pgvector finds nearest neighbor articles
3. Only matching articles' arcs/points are returned
4. Globe updates visualization with filtered data
5. Packet animation continues with new segments
6. Camera flies to first result midpoint

## Styling

Search page uses:
- **Veritas theme**: Dark backgrounds, cyan accents (#38BDF8)
- **JetBrains Mono**: Monospace font for labels
- **Bootstrap 5**: Grid system, buttons, forms
- **Custom animations**: Pulse effect on fire icon, spin on loading

## Performance

- **Debounce**: 300ms on autocomplete input
- **Limit**: Max 100 similar articles per search
- **Cache**: Trending topics cached for 5 minutes (future enhancement)
- **Fallback**: Text search (ILIKE) if embedding fails

## Future Enhancements

- [ ] Advanced filters (date range, source country, threat level)
- [ ] Saved searches / alerts
- [ ] Export search results (CSV, PDF)
- [ ] Multi-query boolean search (AND/OR/NOT)
- [ ] Search history with quick-access
- [ ] Faceted search (by region, source type, topic)

## Troubleshooting

### No Results Found
- Check if articles have embeddings: `Article.where.not(embedding: nil).count`
- Verify OpenRouter API key is set
- Lower similarity threshold in controller

### Globe Not Filtering
- Check browser console for `veritas:search` event
- Ensure globe_controller.js is connected
- Verify /api/globe_data?search_query=... returns filtered data

### Trending Topics Empty
- Ensure AI analysis has `geopolitical_topic` populated
- Check articles from last 7 days exist
- Review TrendingTopicsController logic
