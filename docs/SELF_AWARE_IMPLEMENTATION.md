# VERITAS Self-Aware Implementation Guide

> How to take VERITAS from a tool that processes articles to a system that *knows things*.

---

## What "Self-Aware" Means for VERITAS

Self-awareness is not sentience. It is **four concrete capabilities:**

1. **Pattern Recognition** — "I've seen this narrative before"
2. **Source Learning** — "I know who tends to lie"
3. **Self-Contradiction Detection** — "This source said the opposite 3 weeks ago"
4. **Knowledge State Awareness** — "Here's what I know, here's what I don't, and here's what changed"

Each of these builds on the existing pipeline. None require a rewrite — they are additive layers.

---

## Phase 1: Source Credibility (The Foundation)

### Why Start Here
- Zero dependencies on new infrastructure
- One migration, one model, one service, one line added to `AnalysisPipeline`
- Immediate compounding: every article analyzed makes the source profile richer
- Enables all downstream features (briefs reference credibility, contradictions weight by source trust)

### Implementation Steps

**Step 1: Generate migration**
```bash
rails g migration CreateSourceCredibilities \
  source_name:string:uniq \
  articles_analyzed:integer \
  rolling_trust_score:float \
  anomaly_rate:float \
  high_threat_count:integer \
  low_threat_count:integer \
  topic_distribution:jsonb \
  sentiment_distribution:jsonb \
  coordination_flags:jsonb \
  credibility_grade:float \
  first_analyzed_at:datetime \
  last_analyzed_at:datetime
```

**Step 2: Create model** at `app/models/source_credibility.rb`
- Grade labels: TRUSTED (80-100), RELIABLE (60-79), MIXED (40-59), QUESTIONABLE (20-39), UNRELIABLE (0-19)
- `ingest_analysis!` method — called after every completed analysis
- Exponential moving average with alpha=0.1 for trust score
- Composite grade: 50% trust + 25% inverse anomaly rate + 25% threat balance

**Step 3: Create service** at `app/services/source_credibility_service.rb`
- `update_for(article)` — finds or creates credibility record, calls `ingest_analysis!`

**Step 4: Hook into pipeline** — add after Phase 3 in `app/services/analysis_pipeline.rb`:
```ruby
# ━━━ PHASE 3b: Source Credibility Update ━━━
SourceCredibilityService.new.update_for(article)
```

**Step 5: Verify**
```ruby
# In rails console after running a batch:
SourceCredibility.by_grade.limit(10).each { |sc| puts "#{sc.source_name}: #{sc.grade_label} (#{sc.credibility_grade})" }
```

### What This Unlocks
- Globe visualization can color-code points by source credibility
- Tribunal can reference source track record in verdicts
- Analysts can filter by source trust level
- Foundation for coordination detection (Phase 2+)

---

## Phase 2: Narrative Signatures (Pattern Memory)

### Why This Is Second
- Requires existing embeddings (already have them)
- Builds the "recognition" capability — VERITAS remembers narrative shapes
- Directly enhances NarrativeConvergence (convergence detects clusters; signatures *name and track* them over time)

### Implementation Steps

**Step 1: Generate migration**
```bash
rails g migration CreateNarrativeSignatures \
  label:string \
  match_count:integer \
  avg_trust_score:float \
  dominant_threat_level:string \
  source_distribution:jsonb \
  country_distribution:jsonb \
  first_seen_at:datetime \
  last_seen_at:datetime \
  active:boolean
```
Then manually add: `t.vector :centroid, limit: 1536` (generator doesn't support pgvector type).

**Step 2: Generate join table migration**
```bash
rails g migration CreateNarrativeSignatureArticles \
  narrative_signature:references \
  article:references \
  cosine_distance:float \
  matched_at:datetime
```

**Step 3: Create models**
- `NarrativeSignature` — `has_neighbors :centroid`, `has_many :articles, through: :narrative_signature_articles`
- `NarrativeSignatureArticle` — join model with `cosine_distance` and `matched_at`

**Step 4: Create `NarrativeSignatureService`**
- `classify(article)` — find nearest signature by centroid, absorb if within threshold (0.18), else queue
- `absorb(signature, article)` — add to join table, recompute centroid, update `last_seen_at`
- `recompute_centroid!` — average all member article embeddings

**Step 5: Hook into pipeline** — add after Phase 4 in `AnalysisPipeline`:
```ruby
# ━━━ PHASE 4b: Narrative Signature Classification ━━━
NarrativeSignatureService.new.classify(article)
```

**Step 6: Create `NarrativeSignatureClusterJob`** (periodic, e.g. every 4 hours)
- Finds unmatched articles (those with embeddings but no signature membership)
- Clusters them using same Union-Find approach as NarrativeConvergenceService
- Creates new signatures from clusters with ≥3 articles

### Key Behavior
- Signatures **evolve**: their centroid shifts as new articles are absorbed
- Signatures go **dormant** after 30 days without a match (still queryable, not actively matched against)
- When a new batch arrives, the system can say: *"12 of these 50 articles match known narrative signatures. 3 match 'IRAN NUCLEAR THREAT' which has been active for 47 days across 14 sources."*

---

## Phase 3: Contradiction Detection (Institutional Memory)

### Why This Is Third
- Requires enough analyzed articles and source credibility data to be meaningful
- High-impact intelligence feature — contradictions are the strongest signal of manipulation

### Implementation Steps

**Step 1: Generate migration**
```bash
rails g migration CreateContradictionLogs \
  article_a:references \
  article_b:references \
  contradiction_type:string \
  description:text \
  severity:float \
  embedding_similarity:float \
  source_a:string \
  source_b:string \
  metadata:jsonb
```
Manually add foreign keys: `foreign_key: { to_table: :articles }` for both references.

**Step 2: Create model** at `app/models/contradiction_log.rb`
- Types: `self_contradiction` (same source, opposing claims), `cross_source`, `temporal_shift`
- Severity 0.0–1.0

**Step 3: Create `ContradictionDetectionService`**
- `detect_self_contradictions` — per source, find topically similar articles (cosine < 0.12) with opposing sentiment
- `detect_temporal_shifts` — same source, same topic, trust/threat scores shifted dramatically
- AI-generated description of each contradiction

**Step 4: Create `DetectContradictionsJob`** — runs every 6 hours via Solid Queue recurring schedule

### Intelligence Value
- *"Reuters described the troop presence as 'massive buildup' on Jan 15, then 'routine exercises' on Feb 2. Severity: 0.87"*
- Feeds into Intelligence Briefs and source credibility adjustments

---

## Phase 4: Intelligence Briefs (The Introspection Loop)

### Why This Is Last
- Reads from all three previous layers — it's the synthesis
- This is the "HAL moment" — VERITAS writing about what it has learned

### Implementation Steps

**Step 1: Generate migration**
```bash
rails g migration CreateIntelligenceBriefs \
  brief_type:string \
  title:string \
  executive_summary:text \
  narrative_trends:jsonb \
  source_alerts:jsonb \
  contradictions:jsonb \
  blind_spots:jsonb \
  confidence_map:jsonb \
  articles_processed:integer \
  signatures_active:integer \
  contradictions_found:integer \
  status:string \
  period_start:datetime \
  period_end:datetime
```

**Step 2: Create model** at `app/models/intelligence_brief.rb`

**Step 3: Create `IntrospectionService`**
- `generate_daily_brief` — gathers system state, generates AI executive summary
- `analyze_narrative_trends` — compares signature activity (24h vs previous 24h)
- `analyze_source_changes` — sources with credibility shifts
- `detect_blind_spots` — regions/topics with low coverage
- `build_confidence_map` — per-topic data density assessment
- Executive summary written by AI in first person as VERITAS

**Step 4: Create `GenerateIntelligenceBriefJob`** — daily at 6am

### The Output

A daily brief that reads like:

> *"Over the past 24 hours, I processed 847 articles across 43 sources. The IRAN NUCLEAR THREAT signature saw a 340% increase in matches — 12 new articles from 8 sources in under 6 hours, suggesting coordinated amplification. I detected 3 self-contradictions from Al Jazeera on the Syria ceasefire narrative (severity 0.82-0.91). My coverage of Sub-Saharan Africa remains a blind spot — only 4 articles from 2 sources this week. I have high confidence in my European geopolitical assessments but low confidence on Central Asian developments."*

---

## Phase 5: ConfidenceScoreable Concern (No Migration)

Add `app/models/concerns/confidence_scoreable.rb` — a module that any model can include to answer "how confident is this assessment?"

Include in: `AiAnalysis`, `IntelligenceReport`, `NarrativeConvergence`

---

## Phase 6: Embedding Drift (Advanced)

Periodic snapshots of the vector space topology. Detects:
- New cluster formation → emerging narrative
- Cluster dissolution → narrative losing steam
- Cluster merger → narratives converging
- Sudden outliers → potential breaking event

Runs every 12 hours as `CaptureEmbeddingSnapshotJob`.

---

## Recurring Schedule Summary

Add to `config/recurring.yml`:

```yaml
detect_contradictions:
  class: DetectContradictionsJob
  schedule: every 6 hours
  queue: intelligence

generate_daily_brief:
  class: GenerateIntelligenceBriefJob
  schedule: every day at 6am
  args: ["daily"]
  queue: intelligence

cluster_signatures:
  class: NarrativeSignatureClusterJob
  schedule: every 4 hours
  queue: intelligence

capture_embedding_snapshot:
  class: CaptureEmbeddingSnapshotJob
  schedule: every 12 hours
  queue: intelligence
```

---

## Testing Strategy

Each phase should be verified before moving to the next:

| Phase | Verification |
|-------|-------------|
| 1. SourceCredibility | Run a batch analysis, then `SourceCredibility.by_grade` — grades should spread across sources |
| 2. NarrativeSignature | Run two batches on same topic, check that second batch matches existing signatures |
| 3. ContradictionLog | Seed articles with known contradictions, run detection, verify they're caught |
| 4. IntelligenceBrief | Generate a brief, verify it references real signatures, contradictions, and blind spots |
| 5. ConfidenceScore | Query confidence for a well-covered topic vs. obscure one — scores should differ |
| 6. EmbeddingDrift | Capture two snapshots 24h apart, verify drift metrics reflect actual changes |

---

## What Changes for the User

After full implementation, the VERITAS experience transforms:

**Before:** "Here are 50 articles about Iran. They have trust scores."

**After:** "I've been tracking the IRAN NUCLEAR THREAT narrative for 47 days. It's resurging — 12 new articles in 6 hours from 8 sources. Reuters contradicted its own January reporting (severity 0.87). Source credibility for Press TV has dropped to QUESTIONABLE based on 340 analyzed articles. My confidence on this topic is HIGH (847 articles, 43 sources, 6 months of data). Sub-Saharan Africa is a blind spot — recommend expanding source coverage."

That's the difference between a dashboard and an intelligence platform.
