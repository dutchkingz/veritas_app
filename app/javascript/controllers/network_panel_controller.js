import { Controller } from "@hotwired/stimulus"

// NetworkPanelController — sidebar panel showing connected articles in Network View
//
// Listens for veritas:networkLoaded / veritas:networkCleared events dispatched
// by the globe controller when entering/leaving Network View.
export default class extends Controller {
  connect() {
    this._panel       = document.getElementById("network-panel")
    this._list        = document.getElementById("network-panel-list")
    this._title       = document.getElementById("network-panel-title")
    this._count       = document.getElementById("network-panel-count")
    this._meta        = document.getElementById("network-panel-meta")

    this._onNetworkLoaded  = (e) => this._renderNetwork(e.detail)
    this._onNetworkCleared = ()  => this._clearNetwork()

    window.addEventListener("veritas:networkLoaded",  this._onNetworkLoaded)
    window.addEventListener("veritas:networkCleared",  this._onNetworkCleared)
  }

  disconnect() {
    window.removeEventListener("veritas:networkLoaded",  this._onNetworkLoaded)
    window.removeEventListener("veritas:networkCleared",  this._onNetworkCleared)
  }

  _renderNetwork({ articleId, data, mode }) {
    if (!this._panel || !data) return

    const articles = data.articles || []
    const arcs     = data.arcs || []
    const meta     = data.meta || {}

    // Show the panel
    this._panel.classList.remove("d-none")

    // Find center article
    const center = articles.find(a => a.isCenter) || articles.find(a => a.id === articleId)

    // Title
    if (this._title) {
      this._title.textContent = center ? `NETWORK: ${(center.source || "ARTICLE").toUpperCase()}` : "NARRATIVE NETWORK"
    }

    // Count badge
    if (this._count) {
      this._count.textContent = `${arcs.length} LINKS`
    }

    // Meta line: connection type breakdown
    if (this._meta) {
      const types = meta.connection_types || {}
      const badges = Object.entries(types).map(([type, count]) => {
        const info = this._typeBadgeInfo(type)
        return `<span style="padding:2px 6px;border-radius:3px;background:${info.color}15;color:${info.color};border:1px solid ${info.color}30;font-size:0.65rem;">${info.label}: ${count}</span>`
      }).join("")
      this._meta.innerHTML = badges
    }

    // Build sorted article list (connected articles, sorted by strongest connection)
    const connectedArticles = articles.filter(a => !a.isCenter)

    // Calculate max connection strength per article
    const strengthByArticle = {}
    arcs.forEach(arc => {
      const srcStr = strengthByArticle[arc.sourceArticleId] || 0
      const tgtStr = strengthByArticle[arc.targetArticleId] || 0
      strengthByArticle[arc.sourceArticleId] = Math.max(srcStr, arc.strength || 0)
      strengthByArticle[arc.targetArticleId] = Math.max(tgtStr, arc.strength || 0)
    })

    connectedArticles.sort((a, b) => (strengthByArticle[b.id] || 0) - (strengthByArticle[a.id] || 0))

    // Render list
    if (this._list) {
      this._list.innerHTML = connectedArticles.map(article => {
        const strength = strengthByArticle[article.id] || 0
        const threatColor = this._threatColor(article.threatLevel)
        const connectionArc = arcs.find(a =>
          a.sourceArticleId === article.id || a.targetArticleId === article.id
        )
        const types = connectionArc?.connectionTypes || []
        const typeBadges = types.map(t => {
          const info = this._typeBadgeInfo(t)
          return `<span style="font-size:0.55rem;padding:1px 4px;border-radius:2px;background:${info.color}15;color:${info.color};">${info.label}</span>`
        }).join(" ")

        return `
          <div class="veritas-feed-card network-card"
               data-article-id="${article.id}"
               style="cursor:pointer;border-left:3px solid ${threatColor};padding:8px 10px;margin-bottom:4px;"
               onclick="window.dispatchEvent(new CustomEvent('veritas:exploreArticle', { detail: { articleId: ${article.id} } }))">
            <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:4px;">
              <span class="feed-source" style="font-size:0.7rem;color:#8898a8;text-transform:uppercase;">${article.source || "Unknown"}</span>
              <span style="font-size:0.6rem;color:${threatColor};font-family:'JetBrains Mono',monospace;">${Math.round(strength * 100)}%</span>
            </div>
            <div style="font-size:0.78rem;color:#d0d8e0;line-height:1.3;margin-bottom:4px;display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden;">
              ${article.headline || "Untitled"}
            </div>
            <div style="display:flex;gap:4px;align-items:center;">
              ${typeBadges}
              ${article.country ? `<span style="font-size:0.6rem;color:#506070;margin-left:auto;">${article.country}</span>` : ""}
            </div>
          </div>`
      }).join("")
    }
  }

  _clearNetwork() {
    if (this._panel) this._panel.classList.add("d-none")
    if (this._list) this._list.innerHTML = ""
    if (this._meta) this._meta.innerHTML = ""
  }

  _typeBadgeInfo(type) {
    const map = {
      narrative_route:      { label: "ROUTE",    color: "#a855f7" },
      gdelt_event:          { label: "GDELT",    color: "#ef4444" },
      embedding_similarity: { label: "SEMANTIC",  color: "#3b82f6" },
      shared_entities:      { label: "ENTITIES",  color: "#22c55e" }
    }
    return map[type] || { label: type.toUpperCase(), color: "#6b7280" }
  }

  _threatColor(level) {
    const map = {
      CRITICAL: "#ff4444",
      HIGH: "#ff8c00",
      MODERATE: "#ffd700",
      LOW: "#6088a0",
      NEGLIGIBLE: "#4a5568"
    }
    return map[level] || "#4a5568"
  }
}
