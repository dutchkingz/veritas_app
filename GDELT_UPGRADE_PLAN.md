# GDELT Integration Upgrade Plan
**Erstellt:** 2026-03-24 | **Status:** Phase 1 in Arbeit

---

## Phase 0 Audit — Bestandsaufnahme

### Bestehende GDELT-Dateien

| Datei | Rolle |
|---|---|
| `app/services/gdelt_big_query_service.rb` | Low-level BQ Client, Kostenschutz |
| `app/services/gdelt_ingestion_service.rb` | SQL Builder, Parser, Article-Save |
| `app/jobs/fetch_gdelt_articles_job.rb` | Solid Queue Job, Retry/Discard-Logik |
| `config/recurring.yml` | Cron: stündlich, `:default` Queue |
| `db/schema.rb` | `articles.raw_data` (JSONB), `data_source`, `original_language` |

---

### Das 3-Tier-Sicherheitssystem (KRITISCH — NIE UMGEHEN)

```
TIER 1 — App-Code Paranoia-Check (gdelt_ingestion_service.rb#validate_sql_safety!)
  → Prüft: _PARTITIONTIME vorhanden + LIMIT-Klausel vorhanden
  → Bei Fehler: wirft QueryError BEVOR die Query an BigQuery geht
  → Zweck: Schutz gegen künftige Refactors, die den Partition-Filter droppen

TIER 2 — GdeltBigQueryService (app-seitige Quotas)
  → Dry-Run vor JEDER Query (Google estimatedBytesProcessed)
  → MAX_BYTES_PER_QUERY = 5 GB (per-query Hard-Stop)
  → MAX_BYTES_PER_DAY  = 35 GB (kumulativer Tageszähler in Rails.cache)
  → Bei Überschreitung: wirft QuotaExceededError (kein Retry, sofort discard)
  → Bytezähler: cache_key "gdelt_bq_bytes_today:YYYY-MM-DD", TTL 25h

TIER 3 — Google Cloud Console (server-seitige Limits, code-unabhängig)
  → Budget Alert: $5 → Email-Warnung bei 50%/80%/100%
  → Query Quota: max 10 GB per Query (Google-seitiger Hard-Stop)
  → Projekt-Daily-Limit: 50 GB/Tag (blockiert alle weiteren Queries)
```

**Jede neue Query muss alle 3 Tiers respektieren.**

---

### Aktuelle Query (Baseline)

```sql
SELECT
  DocumentIdentifier,   -- URL
  SourceCommonName,     -- Quellen-Name
  V2Themes,             -- Semicolon-delimited Theme-Codes
  V2Locations,          -- Geocoordinaten-Block (komplex)
  V2Tone,               -- 7 Comma-delimited Floats (nur [0] genutzt!)
  DATE,                 -- YYYYMMDDHHMMSS Integer
  TranslationInfo       -- Sprachcode
FROM `gdelt-bq.gdeltv2.gkg_partitioned`
WHERE _PARTITIONTIME >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR)
  AND (REGEXP_CONTAINS(V2Themes, r'MILITARY') OR ...)   -- 11 Themes
LIMIT 200
```

**Baseline-Scan:** ~178 MB pro Aufruf (laut Logs)
**Budget:** 1 TB/Monat = ~33 GB/Tag = max ~1.4 GB pro stündlichem Aufruf (mit Puffer)
**Status:** Wir sind bei ~0.17 GB pro Aufruf → massiv unter dem Limit.

---

### Was aktuell NICHT genutzt wird (obwohl in der Query)

| Feld | Was wir haben | Was wir machen | Gap |
|---|---|---|---|
| `V2Tone` | 7 Werte (overall, positive, negative, polarity, activity_ref_density, self_group_ref_density, word_count) | Nur `parts[0]` geparst → nicht gespeichert | 6 Werte verworfen, keiner persistiert |
| `V2Locations` | Alle Locations (Type#Name#Country#ADM1#Lat#Lon#FeatureID) | Nur erste Location mit validen Koordinaten | Alle anderen Locations ignoriert |
| `V2Themes` | Hunderte Codes (GCAM_, Topic, TAX_, CRISISLEX_) | Flat Array in `raw_data.gdelt_themes` | Keine Kategorisierung, keine Strukturierung |

---

### Was GDELT zusätzlich liefern könnte (nicht in aktueller Query)

| GKG-Feld | Inhalt | Prio für VERITAS | BigQuery-Impact |
|---|---|---|---|
| `V2Persons` | Named Persons mit CharOffset | **HOCH** (Wer wird erwähnt?) | +5-15% Scan-Größe |
| `V2Organizations` | Named Orgs (NATO, FSB...) | **HOCH** (Welche Akteure?) | +5-10% Scan-Größe |
| `SharingImage` | OG-Image URL | MITTEL (UI ohne Scraping) | +2-3% |
| `V2EnhancedLocations` | Präzisere Koordinaten | MITTEL | +8-12% |
| **Events-Tabelle** | CAMEO Codes, Actor1/2, GoldsteinScale, NumSources | **SEHR HOCH** (Kern der Narrative-Analyse) | Separate Query nötig |

---

## Kostenkalkulation je Phase

| Phase | BigQuery-Änderung | Geschätzte Scan-Größe | Delta |
|---|---|---|---|
| Phase 1 | Keine SQL-Änderung | ~178 MB (unverändert) | 0% |
| Phase 2 | +V2Persons, +V2Organizations, +SharingImage | ~210-250 MB | +18-40% |
| Phase 3 | Neue Events-Query (separat, alle 2h) | ~300-600 MB/Aufruf | Neue Query |

**Alle Phasen bleiben sicher unter dem Budget.**

---

## Implementation-Phasen

### ✅ Phase 1 — Low-Hanging Fruit (KEINE SQL-Änderung)
**Status:** In Arbeit

- [ ] 1.1 V2Tone vollständig parsen + in `raw_data.gdelt_tone` speichern
- [ ] 1.2 Alle Locations parsen + in `raw_data.gdelt_locations` speichern
- [ ] 1.3 Themes kategorisieren (`geopolitical`, `gcam`, `other`)

**SQL-Kosten: ZERO** — alle Felder bereits in der Query.

### ⏸ Phase 2 — Query um neue GKG-Spalten erweitern (Freigabe abwarten)
- [ ] 2.1 `V2Persons` → `raw_data.gdelt_persons[]`
- [ ] 2.2 `V2Organizations` → `raw_data.gdelt_organizations[]`
- [ ] 2.3 `SharingImage` → `raw_data.gdelt_image_url`
- [ ] Cost-Logger: Warnung bei >500 MB, Hard-Stop bei >1 GB pro Query

### ⏸ Phase 3 — GDELT Events-Tabelle (Freigabe abwarten)
- [ ] 3.1 Events-Query designen (QuadClass 3/4 oder GoldsteinScale < -5, NumSources >= 3)
- [ ] 3.2 Neues Model `GdeltEvent`
- [ ] 3.3 URL-Matching-Logik (HTTPS vs HTTP, Query-Parameter stripping)
- [ ] 3.4 CAMEO Code YAML-Mapping
- [ ] Separater Job: alle 2h, eigener High-Water-Mark, volles 3-Tier-Safety

### ⏸ Phase 4 — Sicherheits-Audit & Abschluss (Freigabe abwarten)
- [ ] Kumulativer Byte-Tracker für BEIDE Jobs
- [ ] Regressionstests
- [ ] `GDELT_UPGRADE_REPORT.md`

---

## Offene Fragen / Risiken

1. **GDELT-URLs sind unsauber** — bei Phase 3 Events↔Artikel-Matching brauchen wir robuste URL-Normalisierung (http/https, trailing slashes, Tracking-Parameter). Nicht trivial.
2. **GKG↔Events JOIN** — kein direkter Foreign Key. SOURCEURL-Matching oder separate Ingestion ohne Join.
3. **Scraping-Rate** — GDELT bringt bis zu 200 Artikel/Stunde. FetchArticleContentJob könnte Rate-Limit-Probleme bekommen bei hohem Durchsatz.
4. **`important_stuff.md` Note** — Eine veraltete Notiz sagt "GDELT deaktiviert wegen Problemen". Die aktuelle Implementierung widerspricht dem. **Ist GDELT in Production aktiv?** Klären vor Phase 2.
