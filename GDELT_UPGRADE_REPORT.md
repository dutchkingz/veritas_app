# GDELT Full Integration Upgrade Report
**Erstellt:** 2026-03-24 | **Branch:** `olli/arcvisuals-the-masterpiece-nearly`

---

## Executive Summary

VERITAS nutzt GDELT jetzt auf zwei Ebenen:

| Layer | Tabelle | Was es liefert | Frequenz |
|---|---|---|---|
| **GKG** | `gdeltv2.gkg_partitioned` | Artikel-URLs, Themes, Sentiment, Persons, Orgs, Locations, Images | Stündlich |
| **Events** | `gdeltv2.events` | CAMEO-kodierte Konflikt-Events, Actor1→Actor2 Aktionen, Goldstein-Intensität | Alle 2h |

Beide Jobs sind isoliert, haben unabhängige High-Water-Marks, und teilen denselben `GdeltBigQueryService` mit vollem 3-Tier-Kostenschutz.

---

## Änderungen je Phase

### Phase 1 — GKG-Felder optimiert (commit `5d559d8`)

| Feature | Vorher | Nachher |
|---|---|---|
| V2Tone | Nur Overall geparst, nicht gespeichert | Alle 7 Sub-Scores in `raw_data.gdelt_tone` |
| V2Locations | Nur erste Location | Alle validen Locations in `raw_data.gdelt_locations[]` |
| V2Themes | Flat Array | + `raw_data.gdelt_themes_by_category` (geopolitical/gcam/other) |

**SQL-Kosten:** Keine Änderung (~178 MB/Aufruf).

---

### Phase 2 — GKG-Query um 3 Spalten erweitert

**Neue SELECT-Spalten:** `V2Persons`, `V2Organizations`, `SharingImage`

| Feld | Stored in | Format |
|---|---|---|
| `V2Persons` | `raw_data.gdelt_persons` | `["Vladimir Putin", "Xi Jinping"]` |
| `V2Organizations` | `raw_data.gdelt_organizations` | `["NATO", "UN Security Council"]` |
| `SharingImage` | `raw_data.gdelt_image_url` | `"https://..."` |

**Kosten-Schätzung:**
```
Baseline (Phase 1):  ~178 MB/Aufruf
+V2Persons:          +30–50 MB
+V2Organizations:    +20–40 MB
+SharingImage:       +5–10 MB
─────────────────────────────────
Geschätzt Phase 2:   ~235–280 MB/Aufruf

Stündlich × 24 × 30 = ~169–201 GB/Monat (GKG allein)
→ 17–20% des 1 TB Free Tier Budget
```

**Cost Logger hinzugefügt** in `GdeltBigQueryService`:
- `>500 MB` → `WARN` log
- `>1 GB` → `ERROR` log
- `>5 GB` → `QuotaExceededError` (bestehender Hard-Stop, unverändert)
- Nach Execution: `total_bytes_processed` wird geloggt (nicht nur Estimate)

---

### Phase 3 — GDELT Events-Tabelle integriert

#### Neue Dateien

| Datei | Rolle |
|---|---|
| `db/migrate/20260324120000_create_gdelt_events.rb` | Schema: `gdelt_events` Tabelle |
| `app/models/gdelt_event.rb` | Model mit CAMEO-Lookup, `actor_summary`, Scopes |
| `app/services/gdelt_event_ingestion_service.rb` | SQL Builder, Parser, Save-Logik, URL-Normalizer |
| `app/jobs/fetch_gdelt_events_job.rb` | Solid Queue Job, identische Retry/Discard-Logik wie GKG |
| `config/cameo_codes.yml` | CAMEO Code Lookup (Root Codes + Sub-Codes für Conflict-Bereich) |

#### `gdelt_events` Tabelle (Key Fields)

```
globaleventid          BIGINT UNIQUE   — HWM-Anker, GDELT primary key
event_date             DATE            — für Range-Queries
actor1_name            STRING          — z.B. "RUSSIA"
actor2_name            STRING          — z.B. "UKRAINE"
event_code             STRING          — CAMEO Code z.B. "190" (Fight)
quad_class             INTEGER         — 1=Verbal Coop ... 4=Material Conflict
goldstein_scale        FLOAT           — -10 (destabilizing) bis +10 (stabilizing)
num_sources            INTEGER         — Glaubwürdigkeits-Signal
action_geo_lat/long    FLOAT           — Wo passiert es
source_url_normalized  STRING          — für Article-Matching
article_id             BIGINT (FK)     — nullable, gesetzt wenn URL-Match gefunden
raw_data               JSONB           — Actor1/2 Geo-Koordinaten
```

#### Query-Design

```sql
SELECT GLOBALEVENTID, SQLDATE, Actor1Name, Actor1CountryCode, Actor1Type1Code,
       Actor2Name, Actor2CountryCode, Actor2Type1Code,
       EventCode, EventRootCode, QuadClass, GoldsteinScale,
       NumMentions, NumSources, NumArticles, AvgTone,
       Actor1Geo_Lat, Actor1Geo_Long, Actor2Geo_Lat, Actor2Geo_Long,
       ActionGeo_Lat, ActionGeo_Long, ActionGeo_CountryCode, ActionGeo_FullName,
       SOURCEURL
FROM `gdelt-bq.gdeltv2.events`
WHERE _PARTITIONTIME >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR)
  AND (QuadClass IN (3, 4) OR GoldsteinScale < -5.0)
  AND NumSources >= 3
  AND GLOBALEVENTID > {high_water_mark}
ORDER BY GLOBALEVENTID ASC
LIMIT 500
```

**Filter-Logik:**
- `QuadClass 3/4` = Verbal & Material Conflict (unsere primäre Zielgruppe)
- `GoldsteinScale < -5` = Signifikant destabilisierende Events unabhängig von QuadClass
- `NumSources >= 3` = Mindest-Quellenanzahl gegen Rauschen
- `GLOBALEVENTID > HWM` = Keine Duplikate (HWM = MAX(globaleventid) aus DB)

**Kosten-Schätzung:**
```
Events-Tabelle 24h-Partition:  ~500 MB – 1.5 GB/Scan
Frequenz: alle 2 Stunden       = 12 Scans/Tag
Täglich:                        ~6–18 GB/Tag
Monatlich:                      ~180–540 GB/Monat

Kombiniert (GKG + Events):      ~380–740 GB/Monat
→ Max ~74% des 1 TB Free Tier   ← konservative Schätzung
```

⚠️ **Empfehlung:** Beim ersten Produktions-Run den tatsächlichen Scan-Wert aus den Logs nehmen und die Monatsprognose aktualisieren. Falls Events-Scans konsistent >1 GB, das `INTERVAL 24 HOUR` auf 12h reduzieren (HWM verhindert dann Lücken trotzdem).

#### URL-Normalisierung (Article-Matching)

```
http://reuters.com/article/foo?utm_source=gdelt&ref=bar
→  reuters.com/article/foo

https://www.bbc.co.uk/news/world-12345/
→  bbc.co.uk/news/world-12345
```

Strippt: Schema, `www.`, trailing slashes, Fragments, UTM/Tracking-Parameter.

#### CAMEO-Lookup

`config/cameo_codes.yml` enthält:
- `quad_classes` → "Verbal Conflict", "Material Conflict" etc.
- `root_codes` → alle 20 CAMEO Wurzelcodes
- `codes` → selektive Sub-Codes mit Fokus auf Conflict-Bereich (10–20)

Verwendung:
```ruby
event.event_description  # "Conduct airstrike" (aus event_code "1941")
event.quad_class_label   # "Material Conflict"
event.actor_summary      # "RUSSIA → UKRAINE"
```

#### Actor-Verknüpfung mit NarrativeArcs

`GdeltEvent#article_id` ist der Ankerpunkt. Damit können NarrativeArcs künftig angereichert werden:
```ruby
article.narrative_arcs.first.tap do |arc|
  event = GdeltEvent.where(article_id: arc.article_id).conflicts.first
  arc.update(title: event.actor_summary) if event
end
```
Das bleibt bewusst als **zukünftiger Schritt** außerhalb dieses Upgrades.

---

## Kosten-Gesamtüberblick

| Job | Frequenz | Scan/Aufruf (Schätzung) | GB/Monat |
|---|---|---|---|
| `FetchGdeltArticlesJob` (GKG) | 1x/Stunde | ~250–280 MB | ~180–200 GB |
| `FetchGdeltEventsJob` (Events) | 1x/2 Stunden | ~500 MB–1.5 GB | ~180–540 GB |
| **Gesamt** | | | **~360–740 GB** |
| **Budget** | | | **1.000 GB (Free Tier)** |

→ Worst-case ~74% des Budgets. Empfehlung: Nach den ersten 3 Produktions-Tagen reale Logs auswerten und Schätzung präzisieren.

---

## Deployment-Checkliste

```bash
# 1. Migration ausführen
heroku run rails db:migrate

# 2. Recurring Jobs werden automatisch von Solid Queue registriert
#    (recurring.yml wird beim Dyno-Start eingelesen)

# 3. Ersten Events-Fetch manuell triggern und Kosten prüfen
heroku run rails c
FetchGdeltEventsJob.perform_now

# 4. Logs auf COST WARNING/ALERT prüfen
heroku logs --tail | grep BigQuery

# 5. Nach 24h: Daily Quota Status prüfen
heroku run rake veritas:bq_status
```

---

## Was noch aussteht (Phase 4)

- [ ] Kumulativer Byte-Tracker für beide Jobs kombiniert (GKG + Events)
- [ ] `GdeltEvent` → `NarrativeArc` Anreicherungs-Service
- [ ] Regressionstests: NarrativeArc-Generierung auf GDELT-Events testen
- [ ] GKG-Persons/Orgs in Entity-Mentions-Tabelle integrieren (statt nur in raw_data)
- [ ] Frontend-Komponente: "Conflict Event Overlay" auf dem Globus (CAMEO Quad-Class als Farbe)
