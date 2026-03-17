# Narrative DNA

## What it is

Narrative DNA answers the question: **"How did this story travel, and how was it mutated along the way?"**

It visualizes the propagation chain of a specific article as an interactive force-directed network graph — every media outlet that picked up the story becomes a node, every handoff between outlets becomes an edge.

---

## The data: NarrativeRoutes & Hops

The backbone is the `NarrativeRoute` model (ARCWEAVER 2.0). Each route stores a `hops` JSONB array — a chronological list of outlets that carried the story:

```
Reuters (UK) → BBC (UK) → RT (Russia) → CCTV (China)
  original       amplified   distorted    distorted
```

Each hop records:
- `source_name`, `source_country`, `lat/lng`
- `framing_shift` — how the outlet changed the narrative: `original`, `amplified`, `distorted`, or `neutralized`
- `confidence_score` — how certain ARCWEAVER is of this hop
- `delay_from_previous` — seconds since the previous hop (shows propagation speed)

---

## The backend: NarrativeDnaService

`app/services/narrative_dna_service.rb`

Given an article, it:
1. Loads all `NarrativeRoutes` for that article's arcs
2. Iterates every hop in every route, building **nodes** (unique outlets, deduped by name+country) and **edges** (hop→hop links)
3. The origin hop (index 0) gets `type: "origin"` — rendered larger on the graph
4. `reach` is normalized — outlets that appear across multiple routes get bigger nodes
5. Edges are sorted chronologically by `published_at` for the animated reveal
6. Returns `{ meta, nodes, edges }` — meta includes `manipulation_avg`, `max_manipulation`, `reach_countries`

---

## The frontend: NarrativeDnaController

`app/javascript/controllers/narrative_dna_controller.js`

Triggered by a `veritas:openNarrativeDna` event (fired when you click an arc on the globe or a DNA button on an article card). It:

1. Fetches `/api/narrative_dna/:article_id`
2. Renders a sliding panel with a **D3 force-directed graph** — nodes repel each other, edges act as springs
3. **Origin node** is larger with a pulse ring
4. **Node color** = framing shift color (green=original, amber=amplified, red=distorted, blue=neutralized)
5. **Node size** = reach (how many routes reference that outlet)
6. Edges start invisible, then animate in one by one chronologically (100ms apart) after 800ms — showing the story spreading
7. You can **drag nodes** to reposition them
8. **Hover** shows a tooltip: source, country, framing, confidence, published time
9. **Click a node** → fetches `/api/article_preview/:id` → shows a mini article card at the bottom of the panel

---

## Stats bar

Displayed at the top of the panel:

| Stat | Meaning |
|---|---|
| NODES | Unique media outlets that carried the story |
| ROUTES | Number of propagation paths traced |
| MANIPULATION % | `max_manipulation_score × 100` — how much framing changed from origin to end |
| COUNTRIES | Geographic spread of the narrative |

---

## API

| Endpoint | Handler | Returns |
|---|---|---|
| `GET /api/narrative_dna/:article_id` | `PagesController#narrative_dna` | `{ meta, nodes, edges }` |
| `GET /api/article_preview/:article_id` | `PagesController#article_preview` | Lightweight article card data for node click previews |

---

## Framing shift colors

| Framing | Color | Meaning |
|---|---|---|
| `original` | `#22c55e` (green) | Story reported as-is from origin |
| `amplified` | `#f59e0b` (amber) | Story exaggerated or given outsized prominence |
| `distorted` | `#ef4444` (red) | Framing significantly changed or inverted |
| `neutralized` | `#3b82f6` (blue) | Emotional charge removed, story defused |
