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

export default class extends Controller {
  static targets = ["input", "statusBadge", "fetchingNotice", "clearBtn", "fullSearchLink"]

  connect() {
    this._subscription = null
    this._currentQuery  = null
    // Keep the full-search link href in sync with what's typed
    this._syncLinkHref()
  }

  disconnect() {
    this._unsubscribeFromChannel()
  }

  // ─── Public actions ────────────────────────────────────────────────────────

  async submit(event) {
    event.preventDefault()
    const query = this.inputTarget.value.trim()
    if (query.length < 3) return

    this._currentQuery = query
    this._setLoading(true)

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
    }
  }

  clear() {
    this._currentQuery = null
    this.inputTarget.value = ""

    this._unsubscribeFromChannel()
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

  _handleFreshResults(data) {
    this._hideFetching()
    const prevCount = parseInt(this.statusBadgeTarget?.dataset.cachedCount || "0", 10)
    this._updateBadge(prevCount, data.new_articles_count || 0)

    if ((data.new_articles_count || 0) > 0) {
      // Re-trigger globe to pick up newly-indexed articles
      window.dispatchEvent(new CustomEvent("veritas:search", {
        detail: { query: data.query || this._currentQuery }
      }))

      window.dispatchEvent(new CustomEvent("veritas:fresh-results", {
        detail: { query: data.query, new_count: data.new_articles_count }
      }))
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

    list.innerHTML = articles.slice(0, 8).map(a => this._cardHTML(a)).join("") + `
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
    const trust      = a.trust_score != null ? Math.round(a.trust_score) : "—"
    const threat     = a.threat_level ? `<span class="feed-threat" style="color:${color};">THREAT ${this._esc(a.threat_level)}</span>` : ""
    const geoTag     = a.geo_method === "keyword"
      ? `<span style="font-size:0.6rem;color:#22c55e;margin-left:4px;" title="Real coordinates">◎</span>` : ""

    return `
      <div class="veritas-feed-card"
           style="border-left: 2px solid ${color}30; cursor: pointer;"
           onclick="window.location.assign('/articles/${a.id}')">
        <div class="d-flex justify-content-between align-items-center mb-1">
          <span class="feed-source">${this._esc(a.source_name)}</span>
          <div class="d-flex align-items-center gap-2">
            ${threat}
            <span class="feed-time">${time}</span>
          </div>
        </div>
        <p class="feed-headline" style="font-size:0.78rem; -webkit-line-clamp:2;">
          ${this._esc(a.headline || "No headline")}
        </p>
        <div class="d-flex justify-content-between align-items-center">
          <span class="feed-location">
            <i class="fa fa-map-marker-alt me-1"></i>${country}${geoTag}
          </span>
          <span style="font-family:'JetBrains Mono',monospace;font-size:0.65rem;color:#94a3b8;">
            TRUST: ${trust}%
          </span>
        </div>
      </div>`
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
