import { Controller } from "@hotwired/stimulus"
import * as d3 from "d3"

// EntityNexusController
//
// Renders the Entity Nexus panel — a force-directed graph of entities
// (people, organisations, countries, events) extracted from intelligence articles.
//
// Listens for: veritas:openEntityNexus  — opens panel, optional { articleId } to scope
// Dispatches:  veritas:search           — triggers globe/search filter (Show on Globe)
//
// Node shapes:
//   person       → circle
//   organization → rounded rect
//   country      → hexagon
//   event        → diamond (rotated square)

const TYPE_COLORS = {
  person:       "#38bdf8",
  organization: "#a78bfa",
  country:      "#22c55e",
  event:        "#f59e0b"
}

const TYPE_ICONS = {
  person:       "◉",
  organization: "⬡",
  country:      "◈",
  event:        "◆"
}

export default class extends Controller {
  connect() {
    this._openHandler = (e) => this._onOpen(e)
    window.addEventListener("veritas:openEntityNexus", this._openHandler)
  }

  disconnect() {
    window.removeEventListener("veritas:openEntityNexus", this._openHandler)
    this._cleanup()
  }

  // ─── Entry point ──────────────────────────────────────────────────────────

  async _onOpen(event) {
    const articleId = event?.detail?.articleId || null
    this._cleanup()
    this._renderPanel({ loading: true })

    try {
      const url = articleId
        ? `/api/entity_nexus?article_id=${articleId}&min_mentions=1`
        : `/api/entity_nexus`

      const response = await fetch(url)
      if (!response.ok) throw new Error(`HTTP ${response.status}`)
      const data = await response.json()

      this._renderPanel({ data })
    } catch (err) {
      console.error("[EntityNexus] Failed to load:", err)
      this._renderPanel({ error: true })
    }
  }

  // ─── Panel rendering ──────────────────────────────────────────────────────

  _renderPanel({ loading = false, error = false, data = null }) {
    this._cleanup()

    const panel = document.createElement("div")
    panel.id = "entity-nexus-panel"
    panel.className = "nexus-panel"

    if (loading) {
      panel.innerHTML = this._loadingHTML()
    } else if (error) {
      panel.innerHTML = this._errorHTML()
    } else {
      panel.innerHTML = this._panelHTML(data)
    }

    document.body.appendChild(panel)
    panel.querySelector(".nexus-close")?.addEventListener("click", () => this._cleanup())

    if (data) {
      // Wire Top Actors click → highlight node
      panel.querySelectorAll(".nexus-actor-card").forEach(card => {
        card.addEventListener("click", () => {
          const nodeId = parseInt(card.dataset.entityId, 10)
          this._focusNode(nodeId)
        })
      })

      if (data.nodes?.length > 0) {
        requestAnimationFrame(() => this._renderGraph(data))
      } else {
        const canvas = document.getElementById("nexus-graph-canvas")
        if (canvas) {
          canvas.innerHTML = `
            <div class="nexus-error">
              <div class="nexus-error-icon">⬡</div>
              <div>No entity data yet.</div>
              <div class="nexus-error-sub">Run article analysis to extract entities.</div>
            </div>`
        }
      }
    }

    this._panel = panel
  }

  // ─── D3 Force Graph ───────────────────────────────────────────────────────

  _renderGraph(data) {
    const container = document.getElementById("nexus-graph-canvas")
    if (!container) return

    const width  = container.clientWidth  || 480
    const height = container.clientHeight || 400

    const svg = d3.select(container)
      .append("svg")
      .attr("width", width)
      .attr("height", height)

    // ── Defs: glow filter ──
    const defs = svg.append("defs")

    const glow = defs.append("filter").attr("id", "nexus-glow")
    glow.append("feGaussianBlur").attr("stdDeviation", "3").attr("result", "coloredBlur")
    const merge = glow.append("feMerge")
    merge.append("feMergeNode").attr("in", "coloredBlur")
    merge.append("feMergeNode").attr("in", "SourceGraphic")

    const glowHot = defs.append("filter").attr("id", "nexus-glow-hot")
    glowHot.append("feGaussianBlur").attr("stdDeviation", "5").attr("result", "coloredBlur")
    const mergeHot = glowHot.append("feMerge")
    mergeHot.append("feMergeNode").attr("in", "coloredBlur")
    mergeHot.append("feMergeNode").attr("in", "SourceGraphic")

    // ── Clone data ──
    const nodes    = data.nodes.map(n => ({ ...n }))
    const nodeById = Object.fromEntries(nodes.map(n => [n.id, n]))
    const edges    = data.edges.map(e => ({
      ...e,
      source: nodeById[e.source] || e.source,
      target: nodeById[e.target] || e.target
    }))

    // ── Force simulation ──
    const simulation = d3.forceSimulation(nodes)
      .force("link",      d3.forceLink(edges).id(d => d.id).distance(d => 80 + (10 - Math.min(d.weight, 10)) * 5).strength(0.6))
      .force("charge",    d3.forceManyBody().strength(-220))
      .force("center",    d3.forceCenter(width / 2, height / 2))
      .force("collision", d3.forceCollide().radius(d => this._nodeRadius(d) + 18))

    // ── Edges ──
    const link = svg.append("g")
      .attr("class", "nexus-edges")
      .selectAll("line")
      .data(edges)
      .join("line")
      .attr("stroke",         d => d.avg_sentiment_color || "#64748b")
      .attr("stroke-width",   d => Math.max(0.8, Math.min(d.weight * 0.5, 3.5)))
      .attr("stroke-opacity", 0)
      .attr("filter",         d => d.hot ? "url(#nexus-glow-hot)" : null)

    // ── Node groups ──
    const node = svg.append("g")
      .attr("class", "nexus-nodes")
      .selectAll("g")
      .data(nodes)
      .join("g")
      .attr("class", "nexus-node")
      .style("cursor", "pointer")
      .call(
        d3.drag()
          .on("start", (event, d) => {
            if (!event.active) simulation.alphaTarget(0.3).restart()
            d.fx = d.x; d.fy = d.y
          })
          .on("drag", (event, d) => { d.fx = event.x; d.fy = event.y })
          .on("end",  (event, d) => {
            if (!event.active) simulation.alphaTarget(0)
            d.fx = null; d.fy = null
          })
      )

    // Selection ring
    node.append("circle")
      .attr("class", "nexus-sel-ring")
      .attr("r",              d => this._nodeRadius(d) + 14)
      .attr("fill",           "none")
      .attr("stroke",         "#ffffff")
      .attr("stroke-width",   1.5)
      .attr("stroke-opacity", 0)
      .attr("stroke-dasharray", "4 3")

    // Outer glow ring
    node.append("circle")
      .attr("r",            d => this._nodeRadius(d) + 6)
      .attr("fill",         "none")
      .attr("stroke",       d => d.color)
      .attr("stroke-width", 1)
      .attr("stroke-opacity", 0.25)
      .attr("filter",       "url(#nexus-glow)")

    // Main node shape — varies by entity_type
    node.each(function(d) {
      const g    = d3.select(this)
      const r    = Math.ceil(d._radius = 0) || 1  // computed below via _nodeRadius
      const col  = d.color
      const type = d.entity_type

      if (type === "organization") {
        // Rounded rect
        g.append("rect")
          .attr("class", "nexus-shape")
          .attr("rx", 3).attr("ry", 3)
          .attr("fill",         `${col}18`)
          .attr("stroke",       col)
          .attr("stroke-width", 1.8)
          .attr("filter",       "url(#nexus-glow)")
      } else if (type === "country") {
        // Hexagon polygon
        g.append("polygon")
          .attr("class", "nexus-shape")
          .attr("fill",         `${col}18`)
          .attr("stroke",       col)
          .attr("stroke-width", 1.8)
          .attr("filter",       "url(#nexus-glow)")
      } else if (type === "event") {
        // Diamond
        g.append("rect")
          .attr("class", "nexus-shape nexus-diamond")
          .attr("fill",         `${col}18`)
          .attr("stroke",       col)
          .attr("stroke-width", 1.8)
          .attr("transform",    "rotate(45)")
          .attr("filter",       "url(#nexus-glow)")
      } else {
        // Person: circle
        g.append("circle")
          .attr("class", "nexus-shape")
          .attr("fill",         `${col}18`)
          .attr("stroke",       col)
          .attr("stroke-width", 1.8)
          .attr("filter",       "url(#nexus-glow)")
      }
    })

    // Apply size-dependent attrs now that we know radius values
    node.each(function(d) {
      const ctrl = Object.getPrototypeOf(Object.getPrototypeOf(this))
      const g    = d3.select(this)
      const r    = 0  // will be set in tick via _updateNodeShapes
    })

    this._updateNodeShapes(node)

    // Node label
    node.append("text")
      .attr("class", "nexus-label")
      .attr("dy", d => this._nodeRadius(d) + 11)
      .attr("text-anchor", "middle")
      .text(d => d.name.length > 14 ? d.name.substring(0, 13) + "…" : d.name)

    // Power index badge
    node.append("text")
      .attr("class", "nexus-power-badge")
      .attr("dy", d => -(this._nodeRadius(d) + 5))
      .attr("text-anchor", "middle")
      .attr("fill", d => d.color)
      .text(d => d.power_index >= 20 ? d.power_index : "")

    // ── Tooltip ──
    const tooltip = d3.select(container)
      .append("div")
      .attr("class", "nexus-tooltip")
      .style("opacity", 0)
      .style("pointer-events", "none")

    node
      .on("mouseenter", (event, d) => {
        tooltip.html(this._tooltipHTML(d))
          .style("opacity", 1)
          .style("left", `${event.offsetX + 16}px`)
          .style("top",  `${event.offsetY - 16}px`)
      })
      .on("mousemove", (event) => {
        tooltip
          .style("left", `${event.offsetX + 16}px`)
          .style("top",  `${event.offsetY - 16}px`)
      })
      .on("mouseleave", () => tooltip.style("opacity", 0))
      .on("click", (_event, d) => this._openEntityDetail(d))

    // ── Tick ──
    simulation.on("tick", () => {
      link
        .attr("x1", d => d.source.x)
        .attr("y1", d => d.source.y)
        .attr("x2", d => d.target.x)
        .attr("y2", d => d.target.y)

      node.attr("transform", d => `translate(${d.x},${d.y})`)

      // Update shape positions
      this._updateNodeShapes(node)
    })

    // Reveal edges chronologically after 700ms
    setTimeout(() => {
      link.each(function(d, i) {
        setTimeout(() => {
          d3.select(this)
            .transition().duration(300)
            .attr("stroke-opacity", d.hot ? 0.85 : 0.45)
        }, i * 50)
      })
    }, 700)

    this._simulation = simulation
    this._svg = svg
    this._nodes = nodes
    this._link = link
    this._node = node
  }

  _updateNodeShapes(node) {
    const self = this
    node.each(function(d) {
      const g    = d3.select(this)
      const r    = self._nodeRadius(d)
      const type = d.entity_type

      if (type === "organization") {
        const side = r * 1.7
        g.select(".nexus-shape")
          .attr("x", -side / 2)
          .attr("y", -side / 2)
          .attr("width",  side)
          .attr("height", side)
      } else if (type === "country") {
        g.select(".nexus-shape")
          .attr("points", self._hexPoints(r))
      } else if (type === "event") {
        const side = r * 1.3
        g.select(".nexus-shape")
          .attr("x", -side / 2)
          .attr("y", -side / 2)
          .attr("width",  side)
          .attr("height", side)
      } else {
        g.select(".nexus-shape")
          .attr("r", r)
      }

      g.select(".nexus-sel-ring")
        .attr("r", r + 14)

      g.select(".nexus-label")
        .attr("dy", r + 11)

      g.select(".nexus-power-badge")
        .attr("dy", -(r + 5))
    })
  }

  _hexPoints(r) {
    return Array.from({ length: 6 }, (_, i) => {
      const angle = (Math.PI / 3) * i - Math.PI / 6
      return `${(r * Math.cos(angle)).toFixed(2)},${(r * Math.sin(angle)).toFixed(2)}`
    }).join(" ")
  }

  _nodeRadius(d) {
    const base = d.entity_type === "person" ? 10 : 9
    return base + Math.sqrt(d.power_index || 1) * 0.9
  }

  // ─── Focus a node (from Top Actors click) ────────────────────────────────

  _focusNode(nodeId) {
    if (!this._svg) return
    const d = this._nodes?.find(n => n.id === nodeId)
    if (d) {
      this._openEntityDetail(d)
      // Briefly flash node
      this._svg.selectAll(".nexus-sel-ring")
        .attr("stroke-opacity", n => n.id === nodeId ? 0.8 : 0)
      setTimeout(() => {
        this._svg.selectAll(".nexus-sel-ring")
          .attr("stroke-opacity", 0)
      }, 1800)
    }
  }

  // ─── Entity Detail Panel ─────────────────────────────────────────────────

  async _openEntityDetail(nodeData) {
    const detailEl = document.getElementById("nexus-entity-detail")
    if (!detailEl) return

    detailEl.innerHTML = `<div class="nexus-detail-inner"><div class="nexus-loading-text">LOADING ENTITY DATA...</div></div>`
    detailEl.classList.add("nexus-entity-detail--visible")

    if (this._svg) {
      this._svg.selectAll(".nexus-sel-ring")
        .attr("stroke-opacity", d => d.id === nodeData.id ? 0.75 : 0)
    }

    try {
      const res = await fetch(`/api/entity_nexus/${nodeData.id}`)
      if (!res.ok) throw new Error(`HTTP ${res.status}`)
      const entity = await res.json()
      detailEl.innerHTML = this._detailHTML(entity)
    } catch (err) {
      detailEl.innerHTML = `<div class="nexus-detail-inner"><div class="nexus-error-sub">Failed to load entity data.</div></div>`
    }

    // Wire up buttons
    detailEl.querySelector(".nexus-detail-close")?.addEventListener("click", () => {
      detailEl.classList.remove("nexus-entity-detail--visible")
      setTimeout(() => { detailEl.innerHTML = "" }, 360)
      if (this._svg) this._svg.selectAll(".nexus-sel-ring").attr("stroke-opacity", 0)
    })

    detailEl.querySelector(".nexus-globe-btn")?.addEventListener("click", () => {
      const name = detailEl.querySelector(".nexus-globe-btn")?.dataset.query
      if (name) {
        window.dispatchEvent(new CustomEvent("veritas:search", { detail: { query: name } }))
        this._cleanup()
      }
    })

    detailEl.querySelectorAll(".nexus-article-item").forEach(item => {
      item.addEventListener("click", () => {
        const id = item.dataset.articleId
        if (id) window.location.assign(`/articles/${id}`)
      })
    })

    detailEl.querySelectorAll(".nexus-connected-item").forEach(item => {
      item.addEventListener("click", () => {
        const id = parseInt(item.dataset.entityId, 10)
        if (id) this._focusNode(id)
      })
    })
  }

  // ─── HTML builders ────────────────────────────────────────────────────────

  _panelHTML(data) {
    const { meta, top_actors, nodes, edges } = data
    return `
      <div class="nexus-header">
        <div class="nexus-header-top">
          <div class="nexus-title">◈ ENTITY_NEXUS // INTELLIGENCE WEB</div>
          <button class="nexus-close" aria-label="Close panel">✕</button>
        </div>
        <div class="nexus-stats-row">
          <div class="nexus-stat">
            <span class="nexus-stat-value">${meta.total_entities}</span>
            <span class="nexus-stat-label">ENTITIES</span>
          </div>
          <div class="nexus-stat">
            <span class="nexus-stat-value">${meta.total_mentions}</span>
            <span class="nexus-stat-label">MENTIONS</span>
          </div>
          <div class="nexus-stat">
            <span class="nexus-stat-value">${nodes.length}</span>
            <span class="nexus-stat-label">ACTIVE</span>
          </div>
          <div class="nexus-stat">
            <span class="nexus-stat-value">${edges.length}</span>
            <span class="nexus-stat-label">CONNECTIONS</span>
          </div>
        </div>
        <div class="nexus-legend">
          <span class="nexus-legend-item"><span class="nexus-dot" style="background:#38bdf8"></span>PERSON</span>
          <span class="nexus-legend-item"><span class="nexus-dot" style="background:#a78bfa;border-radius:1px;"></span>ORGANIZATION</span>
          <span class="nexus-legend-item"><span class="nexus-dot" style="background:#22c55e;clip-path:polygon(50% 0%,100% 25%,100% 75%,50% 100%,0% 75%,0% 25%);"></span>COUNTRY</span>
          <span class="nexus-legend-item"><span class="nexus-dot" style="background:#f59e0b;transform:rotate(45deg);border-radius:1px;"></span>EVENT</span>
        </div>
      </div>

      ${top_actors.length > 0 ? this._topActorsHTML(top_actors) : ""}

      <div id="nexus-graph-canvas" class="nexus-graph-canvas"></div>
      <div id="nexus-entity-detail" class="nexus-entity-detail"></div>
    `
  }

  _topActorsHTML(actors) {
    const items = actors.map((a, i) => {
      const sparklineSvg = this._sparklineSVG(a.sparkline || [], a.color)
      return `
        <div class="nexus-actor-card" data-entity-id="${a.id}" style="--actor-color:${a.color};">
          <span class="nexus-actor-rank">#${i + 1}</span>
          <span class="nexus-actor-name">${this._esc(a.name)}</span>
          <span class="nexus-actor-type" style="color:${a.color};">${this._esc(a.entity_type)}</span>
          ${sparklineSvg}
          <span class="nexus-actor-power" style="color:${a.color};">${a.power_index}</span>
        </div>`
    }).join("")

    return `
      <div class="nexus-top-actors">
        <div class="nexus-top-actors-label">▲ TOP ACTORS — POWER INDEX RANKING</div>
        <div class="nexus-actors-list">${items}</div>
      </div>`
  }

  _detailHTML(entity) {
    const color  = entity.color || "#a78bfa"
    const icon   = TYPE_ICONS[entity.entity_type] || "◈"
    const pct    = Math.min(entity.mentions_count / 50 * 100, 100)  // bar width

    const connectedHTML = (entity.connected_entities || []).map(c => `
      <div class="nexus-connected-item" data-entity-id="${c.id}">
        <span class="nexus-connected-dot" style="background:${TYPE_COLORS[c.entity_type] || '#64748b'}"></span>
        <span class="nexus-connected-name">${this._esc(c.name)}</span>
        <span class="nexus-connected-count">${c.shared_articles} shared</span>
      </div>`).join("")

    const articlesHTML = (entity.articles || []).map(a => `
      <div class="nexus-article-item"
           data-article-id="${a.id}"
           style="border-left-color:${a.sentiment_color || '#6b7280'}">
        <div class="nexus-article-headline">${this._esc(a.headline || "—")}</div>
        <div class="nexus-article-meta">
          ${this._esc(a.source_name || "")}
          ${a.country ? `· ${this._esc(a.country)}` : ""}
          ${a.published_at ? `· ${this._timeAgo(new Date(a.published_at))}` : ""}
        </div>
      </div>`).join("")

    const s  = entity.sentiment || {}
    const posW = s.positive || 0
    const neuW = s.neutral  || 0
    const negW = s.negative || 0

    return `
      <div class="nexus-detail-inner">
        <div class="nexus-detail-header">
          <div>
            <div class="nexus-detail-name">${icon} ${this._esc(entity.name)}</div>
          </div>
          <div style="display:flex;align-items:flex-start;gap:6px;">
            <span class="nexus-detail-type" style="color:${color};">${this._esc(entity.entity_type)}</span>
            <button class="nexus-detail-close" aria-label="Close detail">✕</button>
          </div>
        </div>

        <div class="nexus-detail-power-row">
          <div>
            <div class="nexus-detail-power-label">POWER INDEX</div>
          </div>
          <div class="nexus-detail-power-value" style="color:${color};">${entity.power_index || 0}</div>
          <div class="nexus-detail-power-bar-track">
            <div class="nexus-detail-power-bar" style="width:${entity.power_index || 0}%;background:${color};"></div>
          </div>
          <div style="font-family:'JetBrains Mono',monospace;font-size:0.58rem;color:#64748b;flex-shrink:0;">
            ${entity.mentions_count} mentions
          </div>
        </div>

        ${posW + neuW + negW > 0 ? `
        <div class="nexus-detail-section-label">SENTIMENT EXPOSURE</div>
        <div class="nexus-detail-sentiment">
          <div class="nexus-detail-sentiment-bar" style="width:${posW}%;background:#22c55e;"></div>
          <div class="nexus-detail-sentiment-bar" style="width:${neuW}%;background:#475569;"></div>
          <div class="nexus-detail-sentiment-bar" style="width:${negW}%;background:#ef4444;"></div>
        </div>
        <div class="nexus-detail-sentiment-labels">
          <span style="color:#22c55e;">${posW}% positive</span>
          <span>${neuW}% neutral</span>
          <span style="color:#ef4444;">${negW}% negative</span>
        </div>` : ""}

        ${connectedHTML ? `
        <div class="nexus-detail-section-label">CONNECTED ACTORS</div>
        <div class="nexus-connected-list">${connectedHTML}</div>` : ""}

        ${articlesHTML ? `
        <div class="nexus-detail-section-label">INTELLIGENCE SIGNALS</div>
        <div class="nexus-article-list">${articlesHTML}</div>` : ""}

        <button class="nexus-globe-btn" data-query="${this._esc(entity.name)}">
          <i class="fa fa-globe"></i>
          SHOW ON GLOBE — FILTER ALL SIGNALS
        </button>
      </div>
    `
  }

  _loadingHTML() {
    return `
      <div class="nexus-header">
        <div class="nexus-header-top">
          <div class="nexus-title">◈ ENTITY_NEXUS // INTELLIGENCE WEB</div>
          <button class="nexus-close" aria-label="Close panel">✕</button>
        </div>
      </div>
      <div class="nexus-loading">
        <div class="nexus-spinner"></div>
        <div class="nexus-loading-text">MAPPING INTELLIGENCE WEB...</div>
      </div>`
  }

  _errorHTML() {
    return `
      <div class="nexus-header">
        <div class="nexus-header-top">
          <div class="nexus-title">◈ ENTITY_NEXUS // INTELLIGENCE WEB</div>
          <button class="nexus-close" aria-label="Close panel">✕</button>
        </div>
      </div>
      <div class="nexus-error">
        <div class="nexus-error-icon">⬡</div>
        <div>Failed to load entity web.</div>
        <div class="nexus-error-sub">Check server logs.</div>
      </div>`
  }

  _tooltipHTML(d) {
    const icon  = TYPE_ICONS[d.entity_type] || "◈"
    const color = d.color

    return `
      <div class="nexus-tt-name">${icon} ${this._esc(d.name)}</div>
      <div class="nexus-tt-type">${this._esc(d.entity_type)} · ${d.regions} region${d.regions !== 1 ? 's' : ''}</div>
      <div class="nexus-tt-row">
        <span class="nexus-tt-label">POWER INDEX</span>
        <span style="color:${color};font-weight:700;">${d.power_index}</span>
      </div>
      <div class="nexus-tt-row">
        <span class="nexus-tt-label">MENTIONS</span>
        <span>${d.mentions_count}</span>
      </div>
      <div class="nexus-tt-row">
        <span class="nexus-tt-label">AVG THREAT</span>
        <span style="color:${d.avg_sentiment_color}">${d.avg_threat}</span>
      </div>`
  }

  // ─── Sparkline SVG ────────────────────────────────────────────────────────

  _sparklineSVG(data, color) {
    if (!data || data.length === 0) return `<svg class="nexus-actor-sparkline"></svg>`
    const max  = Math.max(...data, 1)
    const w    = 42
    const h    = 18
    const step = w / (data.length - 1 || 1)

    const points = data.map((v, i) => {
      const x = i * step
      const y = h - (v / max) * (h - 2)
      return `${x.toFixed(1)},${y.toFixed(1)}`
    }).join(" ")

    return `
      <svg class="nexus-actor-sparkline" viewBox="0 0 ${w} ${h}" preserveAspectRatio="none">
        <polyline points="${points}"
                  fill="none"
                  stroke="${color}"
                  stroke-width="1.5"
                  stroke-opacity="0.8"
                  stroke-linecap="round"
                  stroke-linejoin="round"/>
      </svg>`
  }

  // ─── Cleanup ──────────────────────────────────────────────────────────────

  _cleanup() {
    this._simulation?.stop()
    this._simulation = null
    this._svg        = null
    this._nodes      = null
    this._link       = null
    this._node       = null
    this._panel      = null

    const panel = document.getElementById("entity-nexus-panel")
    if (panel) {
      panel.classList.add("nexus-panel--closing")
      setTimeout(() => panel.remove(), 290)
    }
  }

  // ─── Utilities ────────────────────────────────────────────────────────────

  _timeAgo(date) {
    const diff = Date.now() - date.getTime()
    const mins = Math.floor(diff / 60000)
    if (mins < 60)  return `${mins}m ago`
    const hrs = Math.floor(mins / 60)
    if (hrs < 24)   return `${hrs}h ago`
    return `${Math.floor(hrs / 24)}d ago`
  }

  _esc(str) {
    return String(str || "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
  }
}
