---
name: V2 Roadmap — Topic Expansion Beyond Geopolitics
description: Future plan to expand narrative tracking beyond geopolitics into health, climate, elections, tech policy. Deferred to V2 to keep API costs low and product focus sharp.
type: project
---

V2 candidate: expand NarrativeRelevanceFilter beyond geopolitics into additional domains.

**Approved domains (ranked by value):**
1. Public Health / Pandemic narratives (anti-vax, pharma disinfo)
2. Climate & Energy (astroturfing, greenwashing, denial networks)
3. Economic Warfare & Sanctions evasion
4. Tech & AI Policy (regulation framing, surveillance debates)
5. Election Integrity (voter fraud narratives, foreign interference)

**Rejected domains:** crime, business/startup, entertainment, sports (unless geopolitically weaponized)

**Implementation approach:** Refactor GeopoliticalRelevanceFilter into a general NarrativeRelevanceFilter with pluggable, toggleable topic modules. Each domain gets its own keyword set and topic-specific threat calibration.

**Why deferred:** API cost control + product focus. Geopolitics alone is a massive surface area for V1. Decision made 2026-03-22.

**How to apply:** Do NOT refactor the filter now. When V2 planning begins, this memory has the approved scope and architecture direction.
