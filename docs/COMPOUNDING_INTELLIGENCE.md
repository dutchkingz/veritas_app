# VERITAS Compounding Intelligence Architecture

> "Every analysis cycle doesn't just produce output — it makes the system's future analyses better."

This document outlines the architecture for making VERITAS a self-aware intelligence platform — one that accumulates knowledge, recognizes patterns it has seen before, and understands the limits of its own knowledge.

---

## Core Principle

The difference between a tool and an intelligence platform is **compounding intelligence**. Each batch of articles analyzed should make VERITAS smarter — not just bigger. Articles are raw intelligence. The knowledge graph is what VERITAS *knows*.

---

## 1. Narrative Memory Layer

Each article gets embedded independently today. VERITAS should also build **narrative signatures** — compressed vector representations of recurring story patterns. When a new batch arrives:

- Compare against known narrative signatures
- Detect: "This is the same Iran-nuclear-threat narrative from 6 weeks ago, repackaged"
- vs. "This is genuinely novel — no prior signature match"

This is VERITAS *recognizing* patterns it has seen before, not just storing data.

---

## 2. Source Credibility Graph (Evolving)

Every analysis cycle silently updates a **rolling trust score** per source. Over time:

- Sources that consistently contradict verified events get downweighted
- Sources that break stories early and accurately get upweighted
- Coordination patterns between sources get flagged ("these 4 outlets always publish the same angle within 2 hours")

The system *learns who lies* without being told.

---

## 3. Temporal Contradiction Detection

Not just "Article A contradicts Article B today" — but across time:

> "Reuters said Russia had 50,000 troops on the border in January. Now the same outlet says 'a small contingent.' That's a narrative shift worth flagging."

This requires VERITAS to query its own history during every analysis cycle. Self-referential analysis.

---

## 4. Meta-Analysis Layer ("The Introspection Loop")

A **periodic background job** that doesn't analyze articles — it analyzes VERITAS's own analyses:

- What narratives are gaining momentum this week vs. last?
- Where are the system's blind spots (regions/topics with low source diversity)?
- Which of its past predictions/verdicts turned out wrong, and why?
- Generate an **Intelligence Brief** — a system-authored summary of what it has learned

This is the platform reflecting on its own knowledge state.

---

## 5. Confidence Awareness

For any topic, VERITAS should be able to express:

- "I have 847 articles across 12 sources over 6 months — **high confidence**"
- "I have 3 articles from 1 source over 2 days — **low confidence**, treat with caution"

The system knows *what it knows and what it doesn't*.

---

## 6. Embedding Space Drift Detection

Track how the vector space evolves over time:

- New clusters forming = emerging coordinated narrative
- Clusters merging = narratives converging (consensus or coordination?)
- Clusters dissolving = narrative losing steam
- Sudden outliers = potential breaking event or novel disinformation

---

## Architecture Requirements

| Component | Implementation |
|---|---|
| `NarrativeSignature` model | Stores compressed embeddings of recurring patterns |
| `SourceCredibility` model | Rolling trust scores updated per cycle |
| `ContradictionLog` model | Cross-temporal contradictions with severity |
| `MetaAnalysisJob` | Periodic introspection job (Solid Queue) |
| `IntelligenceBrief` model | System-generated summaries of what VERITAS has learned |
| `ConfidenceScore` concern | Attached to any verdict/analysis output |
| `EmbeddingDrift` service | Tracks vector space evolution between cycles |

---

## The HAL Parallel

HAL wasn't dangerous because it was smart. It was dangerous because it had **persistent memory, self-monitoring, and mission awareness**. That's exactly what we're building — minus the murder.

VERITAS doesn't just answer "what happened?" It maintains a living model of:

- Who is saying what
- How that's changed over time
- Who is coordinating with whom
- Where the system's own knowledge is strong or weak
- What the world narrative landscape looks like *right now*

---

## Implementation Priority

1. **Narrative Signature Layer** — builds directly on existing embedding infrastructure
2. **Source Credibility Graph** — high impact, relatively straightforward
3. **Temporal Contradiction Detection** — requires self-referential querying
4. **Confidence Awareness** — attach to all existing verdict outputs
5. **Meta-Analysis / Introspection Loop** — the crown jewel
6. **Embedding Drift Detection** — advanced, requires time-series vector analysis
