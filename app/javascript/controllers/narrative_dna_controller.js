import { Controller } from "@hotwired/stimulus"
import * as d3 from "d3"

// NarrativeDnaController
//
// Listens for veritas:openNarrativeDna events (dispatched by globe arc
// clicks and feed card DNA buttons). Fetches /api/narrative_dna/:id,
// then renders a sliding panel with a D3 force-directed network graph
// showing the full source propagation chain.

export default class extends Controller {
  connect() {
    this._openHandler = (e) => this._onOpen(e)
    window.addEventListener("veritas:openNarrativeDna", this._openHandler)
  }

  disconnect() {
    window.removeEventListener("veritas:openNarrativeDna", this._openHandler)
    this._cleanup()
  }

  // -------------------------------------------------------
  // Private
  // -------------------------------------------------------

  async _onOpen(event) {
    const { articleId } = event.detail
    if (!articleId) return

    this._cleanup()
    this._renderPanel({ loading: true })

    try {
      const response = await fetch(`/api/narrative_dna/${articleId}`)
      if (!response.ok) throw new Error(`HTTP ${response.status}`)
      const data = await response.json()
      this._renderPanel({ data })
    } catch (err) {
      console.error("[NarrativeDNA] Failed to load:", err)
      this._renderPanel({ error: true })
    }
  }

  _renderPanel({ loading = false, error = false, data = null }) {
    this._cleanup()

    const panel = document.createElement("div")
    panel.id = "narrative-dna-panel"
    panel.className = "ndna-panel"

    if (loading) {
      panel.innerHTML = this._loadingHTML()
    } else if (error) {
      panel.innerHTML = this._errorHTML()
    } else {
      panel.innerHTML = this._panelHTML(data)
    }

    document.body.appendChild(panel)
    panel.querySelector(".ndna-close")?.addEventListener("click", () => this._cleanup())

    if (data) {
      if (data.nodes?.length > 0) {
        requestAnimationFrame(() => this._renderGraph(data))
      } else {
        const canvas = document.getElementById("ndna-graph-canvas")
        if (canvas) {
          canvas.innerHTML = `
            <div class="ndna-error">
              <div class="ndna-error-icon">◈</div>
              <div>No route data for this signal.</div>
              <div class="ndna-error-sub">Run ARCWEAVER to generate routes.</div>
            </div>`
        }
      }
    }
  }

  _renderGraph(data) {
    const container = document.getElementById("ndna-graph-canvas")
    if (!container) return

    const width  = container.clientWidth  || 420
    const height = container.clientHeight || 480

    const svg = d3.select(container)
      .append("svg")
      .attr("width", width)
      .attr("height", height)

    // ---- Defs: arrow marker + glow filter ----
    const defs = svg.append("defs")

    defs.append("marker")
      .attr("id", "ndna-arrow")
      .attr("viewBox", "0 -4 8 8")
      .attr("refX", 16)
      .attr("refY", 0)
      .attr("markerWidth", 6)
      .attr("markerHeight", 6)
      .attr("orient", "auto")
      .append("path")
      .attr("d", "M0,-4L8,0L0,4")
      .attr("fill", "#00d4ff")
      .attr("opacity", 0.6)

    const glow = defs.append("filter").attr("id", "ndna-glow")
    glow.append("feGaussianBlur").attr("stdDeviation", "2.5").attr("result", "coloredBlur")
    const feMerge = glow.append("feMerge")
    feMerge.append("feMergeNode").attr("in", "coloredBlur")
    feMerge.append("feMergeNode").attr("in", "SourceGraphic")

    // ---- Clone data to avoid D3 mutating the originals ----
    const nodes    = data.nodes.map(n => ({ ...n }))
    const nodeById = Object.fromEntries(nodes.map(n => [n.id, n]))
    const edges    = data.edges.map(e => ({
      ...e,
      source: nodeById[e.source] || e.source,
      target: nodeById[e.target] || e.target
    }))

    // ---- Force simulation ----
    const simulation = d3.forceSimulation(nodes)
      .force("link",      d3.forceLink(edges).id(d => d.id).distance(95).strength(0.75))
      .force("charge",    d3.forceManyBody().strength(-260))
      .force("center",    d3.forceCenter(width / 2, height / 2))
      .force("collision", d3.forceCollide().radius(d => this._nodeRadius(d) + 14))

    // ---- Edges (initially invisible — revealed chronologically) ----
    const link = svg.append("g")
      .attr("class", "ndna-edges")
      .selectAll("line")
      .data(edges)
      .join("line")
      .attr("stroke",         d => d.color || "#00d4ff")
      .attr("stroke-width",   1.6)
      .attr("stroke-opacity", 0)
      .attr("marker-end",     "url(#ndna-arrow)")

    // ---- Nodes ----
    const node = svg.append("g")
      .attr("class", "ndna-nodes")
      .selectAll("g")
      .data(nodes)
      .join("g")
      .attr("class", "ndna-node")
      .style("cursor", "pointer")
      .call(
        d3.drag()
          .on("start", (event, d) => {
            if (!event.active) simulation.alphaTarget(0.3).restart()
            d.fx = d.x
            d.fy = d.y
          })
          .on("drag", (event, d) => {
            d.fx = event.x
            d.fy = event.y
          })
          .on("end", (event, d) => {
            if (!event.active) simulation.alphaTarget(0)
            d.fx = null
            d.fy = null
          })
      )

    // Selection ring (hidden by default, shown on click)
    node.append("circle")
      .attr("class", "ndna-sel-ring")
      .attr("r",            d => this._nodeRadius(d) + 12)
      .attr("fill",         "none")
      .attr("stroke",       "#ffffff")
      .attr("stroke-width", 1.5)
      .attr("stroke-opacity", 0)
      .attr("stroke-dasharray", "4 3")

    // Outer pulse ring — origin nodes only
    node.filter(d => d.type === "origin")
      .append("circle")
      .attr("r",            d => this._nodeRadius(d) + 7)
      .attr("fill",         "none")
      .attr("stroke",       d => d.bias_color)
      .attr("stroke-width", 1)
      .attr("stroke-opacity", 0.3)
      .attr("filter",       "url(#ndna-glow)")

    // Main node circle
    node.append("circle")
      .attr("r",            d => this._nodeRadius(d))
      .attr("fill",         d => `${d.bias_color}1a`)
      .attr("stroke",       d => d.bias_color)
      .attr("stroke-width", d => d.type === "origin" ? 2.5 : 1.5)
      .attr("filter",       "url(#ndna-glow)")

    // Node label
    node.append("text")
      .attr("dy",           d => this._nodeRadius(d) + 12)
      .attr("text-anchor",  "middle")
      .attr("class",        "ndna-label")
      .text(d => (d.source_name || "?").substring(0, 15))

    // ---- Tooltip ----
    const tooltip = d3.select(container)
      .append("div")
      .attr("class", "ndna-tooltip")
      .style("opacity", 0)
      .style("pointer-events", "none")

    node
      .on("mouseenter", (event, d) => {
        tooltip
          .html(this._tooltipHTML(d))
          .style("opacity", 1)
          .style("left",    `${event.offsetX + 16}px`)
          .style("top",     `${event.offsetY - 16}px`)
      })
      .on("mousemove", (event) => {
        tooltip
          .style("left", `${event.offsetX + 16}px`)
          .style("top",  `${event.offsetY - 16}px`)
      })
      .on("mouseleave", () => tooltip.style("opacity", 0))
      .on("click", (_event, d) => {
        this._openNodePreview(d)
      })

    // ---- Tick: update positions ----
    simulation.on("tick", () => {
      link
        .attr("x1", d => d.source.x)
        .attr("y1", d => d.source.y)
        .attr("x2", d => d.target.x)
        .attr("y2", d => d.target.y)

      node.attr("transform", d => `translate(${d.x},${d.y})`)
    })

    // ---- Chronological edge reveal after 800ms ----
    // Nodes settle while edges animate in one by one (100ms apart)
    setTimeout(() => {
      link.each(function (d, i) {
        setTimeout(() => {
          d3.select(this)
            .transition()
            .duration(350)
            .attr("stroke-opacity", 0.7)
        }, i * 100)
      })
    }, 800)

    this._simulation = simulation
    this._svg = svg
  }

  _nodeRadius(d) {
    const base = d.type === "origin" ? 14 : 9
    return base + (d.reach || 0.3) * 8
  }

  _tooltipHTML(d) {
    const shiftColor = d.bias_color || "#6b7280"
    const shift      = (d.framing_shift || "unknown").toUpperCase()
    const conf       = d.confidence != null ? `${(d.confidence * 100).toFixed(0)}%` : "?"
    const time       = d.published_at ? new Date(d.published_at).toLocaleString() : "Unknown"

    return `
      <div class="ndna-tt-source">${d.source_name || "Unknown"}</div>
      <div class="ndna-tt-country">${d.country || "?"}</div>
      <div class="ndna-tt-row">
        <span class="ndna-tt-label">FRAMING</span>
        <span style="color:${shiftColor};font-weight:600;">${shift}</span>
      </div>
      <div class="ndna-tt-row">
        <span class="ndna-tt-label">CONFIDENCE</span>
        <span>${conf}</span>
      </div>
      <div class="ndna-tt-row">
        <span class="ndna-tt-label">PUBLISHED</span>
        <span>${time}</span>
      </div>
    `
  }

  _panelHTML(data) {
    const { meta } = data
    const manipPct   = ((meta.max_manipulation || 0) * 100).toFixed(0)
    const manipColor = meta.max_manipulation > 0.7 ? "#ef4444"
                     : meta.max_manipulation > 0.3 ? "#f59e0b"
                     : "#22c55e"
    const reachCountries = meta.reach_countries ?? "—"

    return `
      <div class="ndna-header">
        <div class="ndna-header-top">
          <div class="ndna-title">NARRATIVE_DNA</div>
          <button class="ndna-close" aria-label="Close panel">✕</button>
        </div>
        <div class="ndna-headline">${meta.headline || "Unknown Signal"}</div>
        <div class="ndna-stats-row">
          <div class="ndna-stat">
            <span class="ndna-stat-value">${meta.total_nodes}</span>
            <span class="ndna-stat-label">NODES</span>
          </div>
          <div class="ndna-stat">
            <span class="ndna-stat-value">${meta.total_routes}</span>
            <span class="ndna-stat-label">ROUTES</span>
          </div>
          <div class="ndna-stat">
            <span class="ndna-stat-value" style="color:${manipColor}">${manipPct}%</span>
            <span class="ndna-stat-label">MANIPULATION</span>
          </div>
          <div class="ndna-stat">
            <span class="ndna-stat-value">${reachCountries}</span>
            <span class="ndna-stat-label">COUNTRIES</span>
          </div>
        </div>
        <div class="ndna-legend">
          <span class="ndna-legend-item"><span class="ndna-dot" style="background:#22c55e"></span>ORIGINAL</span>
          <span class="ndna-legend-item"><span class="ndna-dot" style="background:#f59e0b"></span>AMPLIFIED</span>
          <span class="ndna-legend-item"><span class="ndna-dot" style="background:#ef4444"></span>DISTORTED</span>
          <span class="ndna-legend-item"><span class="ndna-dot" style="background:#3b82f6"></span>NEUTRALIZED</span>
        </div>
      </div>
      <div id="ndna-graph-canvas" class="ndna-graph-canvas"></div>
      <div id="ndna-node-preview" class="ndna-node-preview"></div>
    `
  }

  _loadingHTML() {
    return `
      <div class="ndna-header">
        <div class="ndna-header-top">
          <div class="ndna-title">NARRATIVE_DNA</div>
          <button class="ndna-close" aria-label="Close panel">✕</button>
        </div>
      </div>
      <div class="ndna-loading">
        <div class="ndna-spinner"></div>
        <div class="ndna-loading-text">ANALYZING NARRATIVE STRUCTURE...</div>
      </div>
    `
  }

  _errorHTML() {
    return `
      <div class="ndna-header">
        <div class="ndna-header-top">
          <div class="ndna-title">NARRATIVE_DNA</div>
          <button class="ndna-close" aria-label="Close panel">✕</button>
        </div>
      </div>
      <div class="ndna-error">
        <div class="ndna-error-icon">◈</div>
        <div>Failed to load narrative data.</div>
        <div class="ndna-error-sub">Check server logs.</div>
      </div>
    `
  }

  async _openNodePreview(nodeData) {
    this._selectedNodeId = nodeData.id

    // Update selection rings
    if (this._svg) {
      this._svg.selectAll(".ndna-sel-ring")
        .attr("stroke-opacity", d => d.id === nodeData.id ? 0.7 : 0)
    }

    const preview = document.getElementById("ndna-node-preview")
    if (!preview) return

    // Show loading state immediately
    preview.innerHTML = this._previewLoadingHTML(nodeData)
    preview.classList.add("ndna-node-preview--visible")

    // Wire up close button
    preview.querySelector(".ndna-preview-close")?.addEventListener("click", () => this._closeNodePreview())

    if (!nodeData.article_id) {
      preview.innerHTML = this._previewNoArticleHTML(nodeData)
      preview.querySelector(".ndna-preview-close")?.addEventListener("click", () => this._closeNodePreview())
      return
    }

    try {
      const res = await fetch(`/api/article_preview/${nodeData.article_id}`)
      if (!res.ok) throw new Error(`HTTP ${res.status}`)
      const article = await res.json()
      preview.innerHTML = this._previewHTML(nodeData, article)
    } catch (err) {
      preview.innerHTML = this._previewNoArticleHTML(nodeData)
    }

    preview.querySelector(".ndna-preview-close")?.addEventListener("click", () => this._closeNodePreview())
  }

  _closeNodePreview() {
    this._selectedNodeId = null

    if (this._svg) {
      this._svg.selectAll(".ndna-sel-ring").attr("stroke-opacity", 0)
    }

    const preview = document.getElementById("ndna-node-preview")
    if (preview) {
      preview.classList.remove("ndna-node-preview--visible")
      setTimeout(() => { preview.innerHTML = "" }, 360)
    }
  }

  _previewHTML(nodeData, article) {
    const framingColor = nodeData.bias_color || "#6b7280"
    const framing      = (nodeData.framing_shift || "unknown").toUpperCase()
    const conf         = nodeData.confidence != null ? `${(nodeData.confidence * 100).toFixed(0)}%` : "?"
    const country      = article.country || nodeData.country || "?"
    const pubDate      = article.published_at
      ? new Date(article.published_at).toLocaleDateString("en-GB", { day: "2-digit", month: "short", year: "numeric" })
      : "Unknown"

    return `
      <div class="ndna-preview">
        <div class="ndna-preview-header">
          <span class="ndna-preview-label">NODE PREVIEW</span>
          <button class="ndna-preview-close" aria-label="Close preview">✕</button>
        </div>
        <div class="ndna-preview-meta">
          <span class="ndna-preview-source">${article.source || nodeData.source_name}</span>
          <span class="ndna-preview-framing" style="color:${framingColor}">${framing}</span>
          <span class="ndna-preview-confidence">${conf} CONF</span>
          <span>${country} · ${pubDate}</span>
        </div>
        <div class="ndna-preview-headline">${article.headline || "—"}</div>
        <div class="ndna-preview-snippet">${article.snippet || ""}</div>
        <a class="ndna-preview-link" href="/articles/${article.id}" target="_blank">
          VIEW FULL ARTICLE →
        </a>
      </div>
    `
  }

  _previewLoadingHTML(nodeData) {
    return `
      <div class="ndna-preview">
        <div class="ndna-preview-header">
          <span class="ndna-preview-label">NODE PREVIEW</span>
          <button class="ndna-preview-close" aria-label="Close preview">✕</button>
        </div>
        <div class="ndna-preview-meta">
          <span class="ndna-preview-source">${nodeData.source_name || "Unknown"}</span>
        </div>
        <div class="ndna-preview-no-article">Loading article data…</div>
      </div>
    `
  }

  _previewNoArticleHTML(nodeData) {
    const framingColor = nodeData.bias_color || "#6b7280"
    const framing      = (nodeData.framing_shift || "unknown").toUpperCase()
    const conf         = nodeData.confidence != null ? `${(nodeData.confidence * 100).toFixed(0)}%` : "?"

    return `
      <div class="ndna-preview">
        <div class="ndna-preview-header">
          <span class="ndna-preview-label">NODE PREVIEW</span>
          <button class="ndna-preview-close" aria-label="Close preview">✕</button>
        </div>
        <div class="ndna-preview-meta">
          <span class="ndna-preview-source">${nodeData.source_name || "Unknown"}</span>
          <span class="ndna-preview-framing" style="color:${framingColor}">${framing}</span>
          <span class="ndna-preview-confidence">${conf} CONF</span>
        </div>
        <div class="ndna-preview-no-article">No article record linked to this node.</div>
      </div>
    `
  }

  _cleanup() {
    this._simulation?.stop()
    this._simulation = null
    this._svg = null
    this._selectedNodeId = null
    const panel = document.getElementById("narrative-dna-panel")
    if (panel) {
      panel.classList.add("ndna-panel--closing")
      setTimeout(() => panel.remove(), 290)
    }
  }
}
