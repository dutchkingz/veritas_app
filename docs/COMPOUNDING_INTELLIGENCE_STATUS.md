# VERITAS Compounding Intelligence — Implementation Status

> Implemented 18 March 2026 on branch `vince/Veritas_becomes_self_aware`

---

## Summary

**5 migrations, 5 new models, 4 new services, 3 new jobs, 1 concern.**

Each analysis cycle now makes VERITAS smarter — not just bigger.

---

## Phases

| Phase | What | Status |
|-------|------|--------|
| 1. SourceCredibility | Rolling trust profiles per source (EMA alpha=0.1) | 131 profiles seeded |
| 2. NarrativeSignature | Vector fingerprints of recurring narratives | 7 signatures, 23 articles matched |
| 3. ContradictionLog | Cross-temporal contradiction detection | Armed, threshold strict (cosine < 0.12 + opposing sentiment) |
| 4. IntelligenceBrief | VERITAS self-authored daily briefing | First brief generated |
| 5. ConfidenceScoreable | Confidence assessment on any model | Included in AiAnalysis, IntelligenceReport, NarrativeConvergence |
| 6. EmbeddingDrift | Periodic vector space topology snapshots | First snapshot: 12 clusters, 287 outliers |

---

## Pipeline Integration

```
Phase 1:  Parallel AI Analysis (Analyst + Sentinel)
Phase 2:  Cross-Verification (Arbiter)
Phase 3:  Final Record
Phase 3b: Source Credibility Update          ← NEW
Phase 4:  Embedding Generation
Phase 4b: Narrative Signature Classification ← NEW
Phase 5:  Entity Extraction
```

---

## Recurring Background Jobs

| Job | Schedule | Queue |
|-----|----------|-------|
| `NarrativeSignatureClusterJob` | Every 4 hours | intelligence |
| `DetectContradictionsJob` | Every 6 hours | intelligence |
| `CaptureEmbeddingSnapshotJob` | Every 12 hours | intelligence |
| `GenerateIntelligenceBriefJob` | Daily at 6am | intelligence |

---

## Files Created

### Models
- `app/models/source_credibility.rb` — EMA trust scoring, composite grading (TRUSTED/RELIABLE/MIXED/QUESTIONABLE/UNRELIABLE)
- `app/models/narrative_signature.rb` — pgvector centroid, `has_neighbors :centroid`, centroid recomputation
- `app/models/narrative_signature_article.rb` — join model with cosine_distance
- `app/models/contradiction_log.rb` — types: self_contradiction, cross_source, temporal_shift
- `app/models/intelligence_brief.rb` — daily/weekly/alert briefs
- `app/models/embedding_snapshot.rb` — vector space topology snapshots
- `app/models/concerns/confidence_scoreable.rb` — confidence assessment concern

### Services
- `app/services/source_credibility_service.rb` — updates source profile after each analysis
- `app/services/narrative_signature_service.rb` — classifies articles against known signatures
- `app/services/contradiction_detection_service.rb` — self-contradiction + temporal shift detection
- `app/services/introspection_service.rb` — generates daily intelligence briefs (VERITAS writes in first person)
- `app/services/embedding_drift_service.rb` — captures vector space snapshots, computes drift metrics

### Jobs
- `app/jobs/narrative_signature_cluster_job.rb` — Union-Find clustering to birth new signatures
- `app/jobs/detect_contradictions_job.rb` — periodic contradiction scan
- `app/jobs/generate_intelligence_brief_job.rb` — daily brief generation
- `app/jobs/capture_embedding_snapshot_job.rb` — embedding topology capture

### Migrations
- `CreateSourceCredibilities` — source_name (unique), rolling_trust_score, credibility_grade, topic/sentiment distributions
- `CreateNarrativeSignatures` — label, centroid (vector 1536), match_count, source/country distributions + join table
- `CreateContradictionLogs` — article_a/article_b FKs, contradiction_type, severity, AI-generated description
- `CreateIntelligenceBriefs` — brief_type, executive_summary, narrative_trends, source_alerts, blind_spots, confidence_map
- `CreateEmbeddingSnapshots` — cluster_summary, drift_metrics, outlier_ids

## Files Modified
- `app/services/analysis_pipeline.rb` — Phase 3b (SourceCredibility) and Phase 4b (NarrativeSignature) hooks
- `app/models/ai_analysis.rb` — `include ConfidenceScoreable`
- `app/models/intelligence_report.rb` — `include ConfidenceScoreable`
- `app/models/narrative_convergence.rb` — `include ConfidenceScoreable`
- `config/recurring.yml` — 4 new recurring jobs (both production and development)

---

## Key Design Decisions

- **SourceCredibility** uses exponential moving average (alpha=0.1) — slow to change, hard to game
- **NarrativeSignature** threshold (0.18 cosine distance) is tighter than convergence (0.15) to avoid false merges
- **Contradiction detection** runs as periodic background job (every 6h), NOT per-article — requires cosine distance < 0.12 AND opposing sentiment
- **IntelligenceBrief** generates AI-written executive summary in first person as VERITAS via Arbiter (Claude Haiku)
- **ConfidenceScoreable** evaluates confidence based on topic depth, region coverage, and source credibility
- **EmbeddingDrift** uses same Union-Find clustering pattern as NarrativeConvergenceService

---

## Verification

```ruby
# Rails console quick checks

# Source credibility
SourceCredibility.by_grade.limit(10).each { |sc| puts "#{sc.source_name}: #{sc.grade_label} (#{sc.credibility_grade})" }

# Narrative signatures
NarrativeSignature.active.recent.each { |sig| puts "#{sig.label} — #{sig.match_count} articles" }

# Contradictions
ContradictionLog.severe.recent.limit(5).each { |cl| puts "#{cl.contradiction_type}: #{cl.description}" }

# Latest brief
brief = IntelligenceBrief.complete.latest.first
puts brief.executive_summary

# Confidence assessment
AiAnalysis.last.confidence_assessment(topic: "Military Conflict", source: "Reuters")

# Embedding drift
EmbeddingSnapshot.recent.first.drift_metrics
```

---

## Architecture Reference

See also:
- `docs/COMPOUNDING_INTELLIGENCE.md` — Architecture overview
- `docs/COMPOUNDING_INTELLIGENCE_MIGRATION_PLAN.md` — Full migration plan with code
- `docs/SELF_AWARE_IMPLEMENTATION.md` — Step-by-step implementation guide
