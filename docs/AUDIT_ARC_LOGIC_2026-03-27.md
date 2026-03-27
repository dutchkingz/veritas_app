# VERITAS Arc Logic Audit — 2026-03-27

> **Status: AKTIVE UMSETZUNG**
> Dieses Audit dient als Grundlage fuer die laufende Implementierung.
> Wir arbeiten aktuell daran, die hier dokumentierten Luecken zu schliessen
> und die 4-Type-Connection-Logik vollstaendig in alle Globe-Modi zu integrieren.

---

## Inhaltsverzeichnis

1. [Die 4 Connection-Types im ArticleNetworkService](#1-die-4-connection-types-im-articlenetworkservice)
2. [Search-Flow Gap-Analyse](#2-search-flow-gap-analyse)
3. [_mergeArcSets — Zeile fuer Zeile](#3-_mergearcsetszeile-fuer-zeile)
4. [Legacy-System Bewertung](#4-legacy-system-bewertung)
5. [Umsetzungsplan](#5-umsetzungsplan)

---

## 1. Die 4 Connection-Types im ArticleNetworkService

Definiert in `app/services/article_network_service.rb:15-20`:

```ruby
WEIGHTS = {
  narrative_route:      1.0,
  gdelt_event:          0.8,
  embedding_similarity: 0.6,
  shared_entities:      0.3
}.freeze
```

### Type 1: `narrative_route` (Gewicht 1.0)

**File:** `article_network_service.rb:160-210`

**Logik:** Findet Artikel, die in denselben NarrativeRoute-Hops vorkommen.

- **Z.164:** Holt alle `NarrativeArc`-IDs fuer die gegebenen Artikel
- **Z.167-170:** Laedt alle `NarrativeRoute`s dieser Arcs inkl. Preloads
- **Z.175:** Extrahiert `article_id` aus jedem Hop-JSONB-Feld
- **Z.179:** Vereinigt origin_id + hop_article_ids zur vollen Route
- **Z.186:** Iteriert ueber **konsekutive Paare** (`each_cons(2)`) — also A->B, B->C, etc.
- **Z.200:** Strength = fix `1.0` (volle Gewichtung, kein Decay)
- **Z.202-204:** Metadata: `framing_shift`, `framing_explanation`, `confidence_score` aus Hop-JSONB

**Bewertung:** Staerkstes Signal — echte narrative Propagation. Kein Distanz-Decay, immer 1.0.

### Type 2: `gdelt_event` (Gewicht 0.8)

**File:** `article_network_service.rb:212-267`

**Logik:** Artikel deren GDELT-Events die gleichen Akteure oder Event-Root-Codes teilen.

- **Z.218:** Gruppiert Events nach `article_id`
- **Z.222-226:** Baut einen **Actor-Index** — Key = `normalize_actor_pair(actor1, actor2)` (sortiert, lowercase, Z.682-685)
- **Z.229-231:** Baut einen **EventRootCode-Index** — Key = `event_root_code`
- **Z.237-263:** Iteriert ueber beide Indices, bildet `combination(2)` aus Artikeln im selben Bucket
- **Z.250:** Waehlt das Event mit dem **niedrigsten** GoldsteinScale als `best_event` (= konfliktreichstes)
- **Z.256:** Strength = fix `0.8` (kein Scaling nach Similarity)

**Bewertung:** Solide fuer Real-World-Event-Korrelation. Strength ist konstant 0.8 — kein Gradient nach Event-Aehnlichkeit.

### Type 3: `embedding_similarity` (Gewicht 0.6)

**File:** `article_network_service.rb:269-362`

**Zwei Varianten:**
- `find_embedding_connections` (Z.271-315) — fuer Netzwerk-Expansion (depth traversal)
- `find_embedding_connections_within` (Z.318-362) — nur innerhalb einer gegebenen Artikelmenge

**Logik (Expansion-Variante):**

- **Z.280:** Iteriert ueber Artikel mit Embeddings
- **Z.281-289:** Raw SQL pgvector-Query: `embedding <=> vector` (Cosine Distance), `LIMIT 8` Nachbarn
- **Z.296:** Filtert: `distance >= MAX_COSINE_DISTANCE` (0.35, also Similarity < 0.65) -> raus
- **Z.308:** Strength = `0.6 * (1.0 - distance)` — **skaliert mit Similarity!**
  - Bei 0.65 Similarity -> Strength 0.39
  - Bei 0.95 Similarity -> Strength 0.57

**Within-Variante (Z.318-362):** Gleiche Logik, aber `WHERE id IN (...)` statt freie Suche, `LIMIT 10`.

**Bewertung:** Einziger Type mit dynamischer Strength. Dient als Netzwerk-Expander — findet Verbindungen die kein anderer Typ sieht.

### Type 4: `shared_entities` (Gewicht 0.3)

**File:** `article_network_service.rb:364-411`

**Logik:** Artikel die Named Entities teilen (Personen, Organisationen, Orte).

- **Z.370-385:** Einzelner Raw-SQL-Query ueber `entity_mentions` Self-Join:
  ```sql
  em1.article_id < em2.article_id  -- verhindert Duplikate
  HAVING COUNT(DISTINCT em1.entity_id) >= 2  -- Minimum 2 shared Entities
  ```
- **Z.400:** Strength = `0.3 * log2(shared_count + 1) / log2(5)` — **logarithmischer Decay**:
  - 2 Entities -> `0.3 * 0.68 = 0.20`
  - 4 Entities -> `0.3 * 1.0  = 0.30`
  - 8+ Entities -> geclamped auf max `0.3`
- **Z.406:** Clamp auf `[0.0, 0.3]`

**Bewertung:** Schwaechstes Signal, aber sinnvoll als Bestaetigung anderer Types. Logarithmisch = viele shared Entities bringen kaum mehr als wenige.

### Deduplication & Combined Strength

**File:** `article_network_service.rb:417-465`

- **Z.421:** Pair-Key = sortierte IDs
- **Z.427:** Merged Types werden vereinigt (`.uniq`)
- **Z.430:** Pro Type: max Strength gewinnt
- **Z.449:** Combined Strength = **Summe aller Type-Strengths**, geclamped auf 1.0
- **Z.454:** Filter: alles unter `MIN_STRENGTH = 0.15` fliegt raus

**Beispiel:** Ein Paar mit NarrativeRoute (1.0) + Embedding (0.4) = Combined 1.0 (cap). Ein Paar mit nur Entities (0.2) = 0.2 (knapp ueber Minimum).

---

## 2. Search-Flow Gap-Analyse

> **GAP: Der Search-Flow nutzt den ArticleNetworkService NICHT.**
> Search zeigt aktuell nur NarrativeRoute-basierte Arcs — keine GDELT, keine Entities, keine gewichtete Multi-Type-Logik.

### Aktueller Search-Pfad

**Frontend:** `globe_controller.js:1280-1339` (`_onSearchEvent`)

- **Z.1303-1306:** Baut URL-Params: `search_query=...&view=segments`
- **Z.1312:** Fetcht `${this.dataUrlValue}?${params}` -> `/api/globe_data`

**Backend:** `pages_controller.rb:154-244` (`globe_data`)

- **Z.186-204:** Search-Filter: entweder `ILIKE` (Demo-Mode) oder pgvector nearest-neighbor via `OpenRouterClient.embed`
- **Z.230-244:** Arc-Generierung: **`build_route_segments(filtered_articles, ...)`** -> nur NarrativeRoute-basierte Arcs

### Was fehlt

`globe_data` kennt nur die Legacy-Arc-Logik:
- `build_route_segments` -> NarrativeRoute hops als Arcs
- `build_globe_arcs` -> Fallback Arcs (sentiment-basiert)

**Kein Aufruf von `ArticleNetworkService`** — keine GDELT-Connections, keine Entity-Connections, keine gewichtete Multi-Type-Logik.

### Loesung: Option A (empfohlen)

Search komplett auf ArticleNetworkService umstellen — gleiche Architektur wie Global View:

1. **Frontend** (`globe_controller.js`): `_onSearchEvent` macht nach dem `globe_data`-Fetch einen **zweiten Fetch** auf `/api/article_network/search?search_query=...`, analog zu `_loadGlobalNetworkView` (Z.1413-1483)

2. **Backend** (`pages_controller.rb`): `article_network` Action bekommt einen Search-Mode:
   ```ruby
   if params[:search_query].present?
     search_articles = # gleiche Search-Logik wie globe_data Z.186-204
     data = ArticleNetworkService.new.connections_between(search_articles, time_window: 72.hours)
     render json: data
   end
   ```

3. **Frontend Merge:** Search-Arcs per `_mergeArcSets` mit Legacy-`globe_data`-Arcs kombinieren

### Alternative: Option B

Direkt in `globe_data` (Z.230-244) den `ArticleNetworkService.connections_between(filtered_articles)` aufrufen. Weniger Frontend-Aenderungen, aber vermischt die zwei Systeme.

---

## 3. `_mergeArcSets` — Zeile fuer Zeile

**File:** `globe_controller.js:1555-1573`

```javascript
_mergeArcSets(primary, secondary) {          // Z.1555
    const merged = [...primary]               // Z.1556 — Kopiert ALLE primary Arcs rein
    const existing = new Set()                // Z.1557 — Set fuer Dedup-Keys

    primary.forEach(arc => {                  // Z.1559 — Baut Keys fuer alle Primary-Arcs
      existing.add(                           // Z.1560 — Key = gerundete Coords auf 0.1 Grad
        `${Math.round(arc.startLat * 10)},${Math.round(arc.startLng * 10)}`
        + `-${Math.round(arc.endLat * 10)},${Math.round(arc.endLng * 10)}`
      )
    })                                        // Z.1561

    secondary.forEach(arc => {                // Z.1563 — Iteriert ueber Secondary-Arcs
      const key = ...                         // Z.1564 — Forward-Key
      const keyReverse = ...                  // Z.1565 — Reverse-Key (A->B == B->A)
      if (!existing.has(key)                  // Z.1566 — Nur wenn WEDER forward
          && !existing.has(keyReverse)) {     //          noch reverse existiert
        merged.push(arc)                      // Z.1567 — Hinzufuegen
        existing.add(key)                     // Z.1568 — Registrieren
      }
    })                                        // Z.1569-1570

    return merged                             // Z.1572
}
```

### Verhalten

1. **Primary gewinnt immer** — alle Network-Arcs kommen ungeprfueft rein
2. **Secondary (Legacy-Arcs)** werden nur hinzugefuegt wenn kein Primary-Arc die gleiche Geo-Strecke abdeckt
3. **Dedup-Precision: 0.1 Grad** — ca. 11km. Zwei Arcs Berlin->Moskau werden als Duplikat erkannt, auch wenn Coords leicht abweichen
4. **Bidirektional:** A->B und B->A gelten als gleicher Arc (Reverse-Check Z.1565-1566)

---

## 4. Legacy-System Bewertung

### Aktuell: Legacy wird noch gebraucht

`_loadGlobalNetworkView` (Z.1413-1483) fetcht BEIDE Systeme parallel:

| System | Endpoint | Liefert |
|---|---|---|
| **Network (neu)** | `/api/article_network/global` | Top 25 Threat-Artikel, 4-Type-Connections |
| **Legacy** | `/api/globe_data?view=segments` | ALLE Artikel + Points + Heatmap + Regions + Clusters |

**Gruende warum Legacy noch noetig ist:**

1. **Points + Heatmap + Regions + HeatmapClusters** — diese Daten gibt der `article_network`-Endpoint gar nicht zurueck. Ohne `globe_data` haette der Globe keine Points.

2. **Breitere Arc-Abdeckung** — `globe_data` baut Arcs aus allen NarrativeRoutes aller 250 Artikel. `article_network/global` nur zwischen 25 Top-Threat-Artikeln.

3. **Search View nutzt NUR Legacy** (siehe Gap-Analyse oben).

### Mittelfristig: Legacy-Arcs koennen weg

Bedingungen:
- `article_network` bekommt eigenen Points/Heatmap-Response (oder separater Endpoint)
- `article_network` arbeitet auch fuer Search-Queries
- Artikel-Limitierung von 25 auf ~100 hoch (mit Render-Cap)

Dann waere `globe_data` nur noch fuer Points + Heatmap zustaendig, und **alle Arcs kaemen aus ArticleNetworkService**. Das ist die Ziel-Architektur.

---

## 5. Umsetzungsplan

> **IN ARBEIT — Wir setzen diese Aenderungen aktuell um.**

### Phase 1: Search-Flow Integration (Prioritaet HOCH)

- [ ] `article_network` Action um Search-Mode erweitern
- [ ] `_onSearchEvent` im Frontend auf Dual-Fetch umstellen (globe_data + article_network)
- [ ] `_mergeArcSets` fuer Search-Arcs nutzen

### Phase 2: Global View Optimierung

- [ ] Artikel-Limit von 25 auf 50-100 erhoehen (mit Performance-Test)
- [ ] GDELT Strength dynamisch machen (nicht fix 0.8)
- [ ] Entity-Index auf `entity_mentions(entity_id, article_id)` pruefen

### Phase 3: Legacy-Arc Abloesung

- [ ] Points/Heatmap aus `globe_data` separieren
- [ ] `globe_data` Arcs komplett durch `ArticleNetworkService` ersetzen
- [ ] `build_route_segments` / `build_globe_arcs` Legacy-Code entfernen
- [ ] `_mergeArcSets` entfernen (nicht mehr noetig wenn nur ein Arc-System)

---

*Erstellt: 2026-03-27 | Branch: `olli/gdelt-full-integration`*
*Audit durchgefuehrt auf Basis des vollstaendigen Code-Reads aller relevanten Files mit exakten Zeilennummern.*
