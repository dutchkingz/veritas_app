import { Controller } from "@hotwired/stimulus"
import consumer from "channels/consumer"

// SearchIntelligenceController
//
// Mounts on the navbar search wrapper div.
// Intercepts form submit → POSTs to /api/search → returns cached results instantly.
// Subscribes to IntelligenceSearchChannel for fresh results from FreshIntelligenceJob.
// Dispatches:
//   veritas:search          — globe_controller re-fetches filtered globe data
//   veritas:search-results  — sidebar search panel populates with article cards
//   veritas:search-cleared  — sidebar/toggle hide themselves, globe resets
//   veritas:fresh-results   — fresh data arrived, badge updates + globe re-fetches

const LOADING_STAGES = [
  { delay: 0,    text: "🛰️  SCANNING GLOBAL INTELLIGENCE NETWORKS..." },
  { delay: 2000, text: "🔍  ANALYZING NARRATIVE FRAMING..." },
  { delay: 4000, text: "🌐  GENERATING INTELLIGENCE ROUTES..." }
]

const LOADING_TIMEOUT_MS = 15000

export default class extends Controller {
  static targets = ["input", "statusBadge", "fetchingNotice", "clearBtn", "fullSearchLink"]

  connect() {
    this._subscription    = null
    this._currentQuery    = null
    this._loadingTimers   = []
    this._loadingTimeout  = null
    // Keep the full-search link href in sync with what's typed
    this._syncLinkHref()
  }

  disconnect() {
    this._unsubscribeFromChannel()
    this._clearLoadingTimers()
  }

  // ─── Public actions ────────────────────────────────────────────────────────

  async submit(event) {
    event.preventDefault()
    const query = this.inputTarget.value.trim()
    if (query.length < 3) return

    this._currentQuery = query
    this._setLoading(true)
    this._showLoadingOverlay()

    try {
      const response = await fetch("/api/search", {
        method:  "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content || ""
        },
        body: JSON.stringify({ query })
      })

      if (response.status === 429) {
        this._showNotice("Rate limit reached. Try again in 1 minute.")
        return
      }

      if (!response.ok) {
        const err = await response.json().catch(() => ({}))
        this._showNotice(err.error || "Search failed. Please try again.")
        return
      }

      const data = await response.json()
      this._handleCachedResults(data)

      if (data.notice) this._showNotice(data.notice)

      if (data.fetching_fresh) {
        this._showFetching("Fetching live intelligence...")
        this._subscribeToFreshResults(query)
      }

    } catch (err) {
      console.error("[SearchIntelligenceController] Fetch failed:", err)
      this._showNotice("Search temporarily unavailable.")
    } finally {
      this._setLoading(false)
      // Overlay stays up until fresh results arrive or timeout fires.
      // If there's no live fetch (demo mode / cached only), dismiss it now.
      if (!this._subscription) this._hideLoadingOverlay()
    }
  }

  clear() {
    this._currentQuery = null
    this.inputTarget.value = ""

    this._unsubscribeFromChannel()
    this._hideLoadingOverlay()
    this._hideFetching()
    this._hideBadge()
    this._clearSearchPanel()
    this._globeGlow(false)

    if (this.hasClearBtnTarget) this.clearBtnTarget.classList.add("d-none")

    window.dispatchEvent(new CustomEvent("veritas:searchClear"))   // globe resets
    window.dispatchEvent(new CustomEvent("veritas:search-cleared")) // view toggle hides
  }

  // ─── Result handling ───────────────────────────────────────────────────────

  _handleCachedResults(data) {
    this._updateBadge(data.total_cached, 0)
    if (this.hasClearBtnTarget) this.clearBtnTarget.classList.remove("d-none")

    this._renderSearchPanel(data.cached_results || [], data.query)
    this._globeGlow(true)

    // Tell the globe to filter (existing event it already listens for)
    window.dispatchEvent(new CustomEvent("veritas:search", {
      detail: { query: data.query }
    }))

    // Tell view toggle + any other listeners
    window.dispatchEvent(new CustomEvent("veritas:search-results", {
      detail: {
        query:         data.query,
        cached_results: data.cached_results,
        total_cached:  data.total_cached,
        fetching_fresh: data.fetching_fresh
      }
    }))
  }

  async _handleFreshResults(data) {
    this._hideLoadingOverlay()
    this._hideFetching()
    const newCount = data.new_articles_count || 0
    const query    = data.query || this._currentQuery

    if (newCount > 0) {
      // Re-fetch search results so the sidebar shows the newly saved articles
      try {
        const response = await fetch("/api/search", {
          method:  "POST",
          headers: {
            "Content-Type": "application/json",
            "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content || ""
          },
          body: JSON.stringify({ query })
        })
        if (response.ok) {
          const freshData = await response.json()
          this._renderSearchPanel(freshData.cached_results || [], freshData.query)
          this._updateBadge(freshData.total_cached, newCount)
        }
      } catch (err) {
        // Non-fatal — badge still shows new count
        const prevCount = parseInt(this.statusBadgeTarget?.dataset.cachedCount || "0", 10)
        this._updateBadge(prevCount, newCount)
        console.warn("[SearchIntelligenceController] Re-fetch after fresh results failed:", err)
      }

      // Tell the globe to re-filter with newly indexed articles
      window.dispatchEvent(new CustomEvent("veritas:search", { detail: { query } }))
      window.dispatchEvent(new CustomEvent("veritas:fresh-results", {
        detail: { query, new_count: newCount }
      }))
    } else {
      const prevCount = parseInt(this.statusBadgeTarget?.dataset.cachedCount || "0", 10)
      this._updateBadge(prevCount, 0)
    }

    this._unsubscribeFromChannel()
  }

  // ─── ActionCable subscription ──────────────────────────────────────────────

  _subscribeToFreshResults(query) {
    this._unsubscribeFromChannel()

    // Match Rails' parameterize: lowercase, replace non-alphanumeric with hyphens
    const parameterized = query.toLowerCase()
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-|-$/g, "")

    this._subscription = consumer.subscriptions.create(
      { channel: "IntelligenceSearchChannel", query: parameterized },
      {
        received: (data) => {
          if (data.type === "fresh_results_ready") {
            this._handleFreshResults(data)
          }
        }
      }
    )
  }

  _unsubscribeFromChannel() {
    if (this._subscription) {
      this._subscription.unsubscribe()
      this._subscription = null
    }
  }

  // ─── Search results sidebar panel ─────────────────────────────────────────

  _renderSearchPanel(articles, query) {
    const panel   = document.getElementById("intel-search-panel")
    const list    = document.getElementById("intel-search-results")
    const header  = document.getElementById("intel-search-header")
    const counter = document.getElementById("intel-search-count")

    if (!panel || !list) return

    panel.classList.remove("d-none")

    if (header)  header.textContent  = `QUERY: "${query.toUpperCase().slice(0, 24)}"`
    if (counter) counter.textContent = articles.length

    if (articles.length === 0) {
      list.innerHTML = `
        <div style="padding: 12px 8px; font-family: 'JetBrains Mono', monospace;
                    font-size: 0.72rem; color: #475569; text-align: center;">
          No cached signals. Fetching live data...
        </div>`
      return
    }

    // Rank articles: relevance (position order) × threat × recency
    const ranked = this._rankSearchResults(articles)

    list.innerHTML = ranked.slice(0, 8).map(a => this._cardHTML(a)).join("") + `
      <div style="padding: 8px 4px 4px;">
        <a href="/search?q=${encodeURIComponent(query)}" target="_blank"
           style="font-family: 'JetBrains Mono', monospace; font-size: 0.65rem;
                  color: #00f0ff; text-decoration: none; letter-spacing: 0.06em;
                  display: flex; align-items: center; gap: 6px; opacity: 0.7;"
           onmouseover="this.style.opacity='1'" onmouseout="this.style.opacity='0.7'">
          <i class="fa fa-external-link-alt" style="font-size: 0.6rem;"></i>
          OPEN FULL SEARCH PAGE →
        </a>
      </div>`
  }

  // Composite ranking: relevance × 0.5 + threat × 0.3 + recency × 0.2
  _rankSearchResults(articles) {
    const now = Date.now()
    const maxHours = 168  // 7 days
    const hardCutoff = 14 * 24  // 14 days → heavy penalty

    const threatMap = { CRITICAL: 1.0, HIGH: 0.75, MODERATE: 0.5, LOW: 0.25, NEGLIGIBLE: 0.1 }

    return articles.map((a, idx) => {
      // Relevance: position in backend results (already ordered by relevance)
      const relevance = 1.0 - (idx / Math.max(articles.length, 1))

      // Threat: normalized from threat_level string
      const threatNorm = threatMap[a.threat_level] || 0.15

      // Recency: hours since published, decay over maxHours, heavy penalty after hardCutoff
      let recency = 0.5  // default for missing date
      if (a.published_at) {
        const hoursSince = (now - new Date(a.published_at).getTime()) / 3600000
        if (hoursSince > hardCutoff) {
          recency = 0.05  // >14 days = near-zero
        } else {
          recency = Math.max(0, 1.0 - (hoursSince / maxHours))
        }
      }

      const score = relevance * 0.5 + threatNorm * 0.3 + recency * 0.2
      return { ...a, _rankScore: score, _threatNorm: threatNorm }
    }).sort((a, b) => b._rankScore - a._rankScore)
  }

  _clearSearchPanel() {
    const panel = document.getElementById("intel-search-panel")
    const list  = document.getElementById("intel-search-results")
    if (panel) panel.classList.add("d-none")
    if (list)  list.innerHTML = ""
  }

  _cardHTML(a) {
    const time       = a.published_at ? this._timeAgo(new Date(a.published_at)) : "—"
    const color      = a.sentiment_color || "#00f0ff"
    const country    = this._esc(a.country || "Unknown")
    const threat     = a.threat_level ? `<span class="feed-threat" style="color:${color};">THREAT ${this._esc(a.threat_level)}</span>` : ""

    // Threat indicator dot — red/yellow/green based on threat_level
    const threatNorm = a._threatNorm != null ? a._threatNorm : { CRITICAL: 1.0, HIGH: 0.75, MODERATE: 0.5, LOW: 0.25 }[a.threat_level] || 0
    const dotColor   = threatNorm > 0.7 ? '#ff4444' : threatNorm >= 0.4 ? '#ffd700' : '#22c55e'
    const threatDot  = `<span style="display:inline-block;width:6px;height:6px;border-radius:50%;background:${dotColor};box-shadow:0 0 4px ${dotColor}60;margin-right:4px;" title="Threat: ${a.threat_level || 'N/A'}"></span>`

    const geoTag     = a.geo_method === "keyword"
      ? `<span style="font-size:0.6rem;color:#22c55e;margin-left:4px;" title="Real coordinates">◎</span>` : ""

    const hasJourney  = !!a.journey_data
    const journeyAttr = hasJourney
      ? `data-feed-card-journey-available-value="true" data-feed-card-journey-value="${this._esc(JSON.stringify(a.journey_data))}"`
      : `data-feed-card-journey-available-value="false"`

    const journeyBtns = hasJourney ? `
        <button class="vt-feed-journey-btn vt-feed-journey-btn--bloom"
                type="button"
                data-action="click->feed-card#openBloom"
                title="Watch the narrative bloom across the globe">◉ BLOOM</button>
        <button class="vt-feed-journey-btn vt-feed-journey-btn--chronicle"
                type="button"
                data-action="click->feed-card#openChronicle"
                title="Step through the narrative route hop by hop">▶ CHRONICLE</button>` : ""

    return `
      <div class="veritas-feed-card"
           style="border-left: 2px solid ${color}30;"
           data-controller="feed-card"
           data-feed-card-lat-value="${a.latitude || ""}"
           data-feed-card-lng-value="${a.longitude || ""}"
           data-feed-card-article-id-value="${a.id}"
           ${journeyAttr}
           data-article-id="${a.id}"
           data-action="click->feed-card#select">
        <div class="d-flex justify-content-between align-items-center mb-1">
          <span class="feed-source">${threatDot}${this._esc(a.source_name)}</span>
          <div class="d-flex align-items-center gap-2">
            ${threat}
            <span class="feed-time">${time}</span>
            <a href="/articles/${a.id}"
               class="feed-card-open-link"
               style="font-size:0.7rem;color:rgba(0,240,255,0.4);text-decoration:none;"
               data-turbo="false"
               data-action="click->feed-card#openArticle">→</a>
          </div>
        </div>
        <p class="feed-headline" style="font-size:0.78rem; -webkit-line-clamp:2;">
          ${this._esc(a.headline || "No headline")}
        </p>
        <div class="d-flex justify-content-between align-items-center">
          <span class="feed-location">
            <i class="fa fa-map-marker-alt me-1"></i>${country}${geoTag}
          </span>
          <div class="d-flex align-items-center gap-1 flex-wrap justify-content-end">
            ${journeyBtns}
            <button class="ndna-trigger-btn"
                    type="button"
                    style="font-family:'JetBrains Mono',monospace;font-size:0.55rem;padding:1px 4px;border:1px solid rgba(0,240,255,0.2);background:transparent;color:#00f0ff;"
                    data-action="click->feed-card#openDna"
                    title="View Narrative DNA">◈ DNA</button>
            <button class="tribunal-trigger-btn"
                    type="button"
                    style="font-family:'JetBrains Mono',monospace;font-size:0.55rem;padding:1px 4px;border:1px solid rgba(0,240,255,0.2);background:transparent;color:#00f0ff;"
                    data-action="click->feed-card#openTribunal"
                    title="Open Intelligence Tribunal">⬟ TRIBUNAL</button>
            <button class="nexus-trigger-btn"
                    type="button"
                    style="font-family:'JetBrains Mono',monospace;font-size:0.55rem;padding:1px 4px;border:1px solid rgba(167,139,250,0.2);background:transparent;color:#a78bfa;"
                    data-action="click->feed-card#openNexus"
                    title="Open Entity Nexus for this article">◈ NEXUS</button>
          </div>
        </div>
      </div>`
  }

  // ─── Cinematic loading overlay ─────────────────────────────────────────────

  _showLoadingOverlay() {
    const overlay = document.getElementById("intel-loading-overlay")
    const stage   = document.getElementById("intel-loading-stage")
    if (!overlay) return

    this._clearLoadingTimers()
    overlay.classList.remove("is-fading")
    overlay.classList.add("is-visible")

    // Cycle through staged messages
    LOADING_STAGES.forEach(({ delay, text }) => {
      const t = setTimeout(() => {
        if (stage) stage.textContent = text
      }, delay)
      this._loadingTimers.push(t)
    })

    // Fallback timeout — show "no results" message and dismiss
    this._loadingTimeout = setTimeout(() => {
      if (stage) stage.textContent = "⚠️  NO FRESH INTELLIGENCE FOUND — SHOWING CACHED RESULTS"
      setTimeout(() => this._hideLoadingOverlay(), 2500)
    }, LOADING_TIMEOUT_MS)
  }

  _hideLoadingOverlay() {
    const overlay = document.getElementById("intel-loading-overlay")
    if (!overlay) return

    this._clearLoadingTimers()
    overlay.classList.add("is-fading")
    setTimeout(() => {
      overlay.classList.remove("is-visible", "is-fading")
    }, 650)
  }

  _clearLoadingTimers() {
    this._loadingTimers.forEach(t => clearTimeout(t))
    this._loadingTimers = []
    if (this._loadingTimeout) {
      clearTimeout(this._loadingTimeout)
      this._loadingTimeout = null
    }
  }

  // ─── UI helpers ────────────────────────────────────────────────────────────

  _setLoading(loading) {
    this.element.classList.toggle("is-loading", loading)
    if (loading) {
      this.inputTarget.style.boxShadow = "0 0 0 2px rgba(0,240,255,0.4)"
    } else {
      this.inputTarget.style.boxShadow = ""
    }
  }

  _showFetching(msg) {
    if (!this.hasFetchingNoticeTarget) return
    this.fetchingNoticeTarget.textContent = msg
    this.fetchingNoticeTarget.classList.remove("d-none")
  }

  _hideFetching() {
    if (this.hasFetchingNoticeTarget) this.fetchingNoticeTarget.classList.add("d-none")
  }

  _showNotice(msg) {
    if (!this.hasFetchingNoticeTarget) return
    this.fetchingNoticeTarget.textContent = msg
    this.fetchingNoticeTarget.style.color = "#f59e0b"
    this.fetchingNoticeTarget.classList.remove("d-none")
    setTimeout(() => {
      this._hideFetching()
      if (this.hasFetchingNoticeTarget) this.fetchingNoticeTarget.style.color = ""
    }, 5000)
  }

  _updateBadge(cached, fresh) {
    if (!this.hasStatusBadgeTarget) return
    const badge = this.statusBadgeTarget
    badge.dataset.cachedCount = cached
    badge.classList.remove("d-none")
    if (fresh > 0) {
      badge.textContent      = `${cached} + ${fresh} fresh`
      badge.style.color      = "#22c55e"
    } else {
      badge.textContent      = `${cached} cached`
      badge.style.color      = "#00f0ff"
    }
  }

  _hideBadge() {
    if (this.hasStatusBadgeTarget) this.statusBadgeTarget.classList.add("d-none")
  }

  _globeGlow(on) {
    const section = document.querySelector(".veritas-globe-section")
    if (!section) return
    if (on) {
      section.style.borderTop  = "2px solid rgba(0,240,255,0.35)"
      section.style.boxShadow  = "inset 0 3px 30px rgba(0,240,255,0.07)"
    } else {
      section.style.borderTop  = ""
      section.style.boxShadow  = ""
    }
  }

  // ─── Utilities ─────────────────────────────────────────────────────────────

  _syncLinkHref() {
    if (!this.hasFullSearchLinkTarget) return
    const q = this.inputTarget.value.trim()
    this.fullSearchLinkTarget.href = q.length >= 3
      ? `/search?q=${encodeURIComponent(q)}`
      : "/search"
    this.inputTarget.addEventListener("input", () => {
      const val = this.inputTarget.value.trim()
      this.fullSearchLinkTarget.href = val.length >= 3
        ? `/search?q=${encodeURIComponent(val)}`
        : "/search"
    })
  }

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
