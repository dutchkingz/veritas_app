import { Controller } from "@hotwired/stimulus"
import consumer from "channels/consumer"

// Breaking Intelligence Alert System
// Listens on AlertsChannel, renders cinematic overlay, dispatches globe event.
// Stealth trigger: Shift+Ctrl+B keyboard shortcut or hidden pixel click.

const ALERT_DURATION_MS = 8000 // auto-dismiss after 8s
const CSRF_TOKEN = () => document.querySelector('meta[name="csrf-token"]')?.content

export default class extends Controller {
  connect() {
    console.log("[VERITAS] BreakingAlertController connected ✓")
    this._subscription = consumer.subscriptions.create("AlertsChannel", {
      connected:    ()     => console.log("[VERITAS] AlertsChannel WebSocket connected ✓"),
      disconnected: ()     => console.warn("[VERITAS] AlertsChannel WebSocket disconnected"),
      received:     (data) => { console.log("[VERITAS] AlertsChannel received:", data); this._onBroadcast(data) }
    })

    this._keyHandler   = (e) => this._onKeyDown(e)
    this._surgeHandler = ()  => this.triggerSurgeCheck()
    window.addEventListener("keydown", this._keyHandler)
    document.addEventListener("veritas:trigger-surge", this._surgeHandler)
    console.log("[VERITAS] BreakingAlertController connected ✓")
  }

  disconnect() {
    this._subscription?.unsubscribe()
    window.removeEventListener("keydown", this._keyHandler)
    document.removeEventListener("veritas:trigger-surge", this._surgeHandler)
    this._removeOverlay()
  }

  // -------------------------------------------------------
  // Broadcast handler
  // -------------------------------------------------------

  _onBroadcast(data) {
    if (data.type !== "breaking_alert") return
    this._showAlert(data.alert)
    this._notifyGlobe(data.alert)
  }

  // -------------------------------------------------------
  // Stealth triggers
  // -------------------------------------------------------

  _onKeyDown(e) {
    // Mac: Cmd+Shift+X  |  Win/Linux: Ctrl+Shift+X
    const trigger = e.shiftKey && (e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "x"
    if (trigger) {
      e.preventDefault()
      document.dispatchEvent(new CustomEvent("veritas:trigger-surge"))
    }
  }

  // Public — called via data-action="click->breaking-alert#triggerSurgeCheck"
  async triggerSurgeCheck() {
    console.log("[VERITAS] Surge check triggered...")
    try {
      const res  = await fetch("/api/surge_check", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": CSRF_TOKEN()
        },
        body: JSON.stringify({ force: true })
      })
      const json = await res.json()
      console.log("[VERITAS] Surge check response:", json)
    } catch (err) {
      console.error("[VERITAS] Surge check failed:", err)
    }
  }

  // -------------------------------------------------------
  // Overlay rendering
  // -------------------------------------------------------

  _showAlert(alert) {
    this._removeOverlay() // Remove any existing overlay

    const overlay = document.createElement("div")
    overlay.id = "ba-overlay"
    overlay.className = "breaking-alert-overlay"
    overlay.setAttribute("data-severity", alert.severity)

    overlay.innerHTML = this._buildHTML(alert)
    document.body.appendChild(overlay)

    // Wire dismiss button
    overlay.querySelector(".breaking-alert-dismiss")
      ?.addEventListener("click", () => this._removeOverlay())

    // Auto-dismiss
    this._dismissTimer = setTimeout(() => this._removeOverlay(), ALERT_DURATION_MS)

    // Start typewriter effect on briefing text
    this._typewrite(
      overlay.querySelector(".breaking-alert-briefing"),
      alert.briefing
    )
  }

  _buildHTML(alert) {
    const severity = (alert.severity || "critical").toUpperCase()
    const now = new Date().toISOString().replace("T", " ").substring(0, 19) + " UTC"
    const sources = alert.source_count > 0 ? alert.source_count : "—"
    const articles = alert.article_count > 0 ? alert.article_count : "—"

    return `
      <div class="breaking-alert-scanline"></div>
      <div class="breaking-alert-panel">
        <div class="breaking-alert-header">
          <div class="d-flex align-items-center gap-3">
            <span class="breaking-alert-label">⬤ BREAKING INTELLIGENCE</span>
            <span class="breaking-alert-severity">${severity}</span>
          </div>
          <span class="breaking-alert-timestamp">${now}</span>
        </div>

        <div class="breaking-alert-body">
          <div class="breaking-alert-headline">
            <span class="ba-surge-prefix">//</span>${this._escapeHtml(alert.headline)}
          </div>
          <div class="breaking-alert-briefing"></div>

          <div class="breaking-alert-meta">
            <div class="breaking-alert-meta-item">
              REGION <span class="ba-meta-value">${this._escapeHtml(alert.region_name)}</span>
            </div>
            <div class="breaking-alert-meta-item">
              SOURCES <span class="ba-meta-value">${sources}</span>
            </div>
            <div class="breaking-alert-meta-item">
              ARTICLES <span class="ba-meta-value">${articles}</span>
            </div>
            <div class="breaking-alert-meta-item">
              COORDS <span class="ba-meta-value">${alert.lat?.toFixed(2)}° / ${alert.lng?.toFixed(2)}°</span>
            </div>
          </div>
        </div>

        <div class="breaking-alert-footer">
          <div class="breaking-alert-countdown-bar" style="--ba-duration: ${ALERT_DURATION_MS / 1000}s">
            <div class="ba-countdown-fill"></div>
          </div>
          <button class="breaking-alert-dismiss">ACKNOWLEDGE</button>
        </div>
      </div>
    `
  }

  _removeOverlay() {
    clearTimeout(this._dismissTimer)
    document.getElementById("ba-overlay")?.remove()
  }

  // -------------------------------------------------------
  // Typewriter effect
  // -------------------------------------------------------

  _typewrite(el, text) {
    if (!el || !text) return
    el.textContent = ""
    let i = 0
    const interval = setInterval(() => {
      el.textContent += text[i]
      i++
      if (i >= text.length) clearInterval(interval)
    }, 18) // ~55 chars/sec — reads fast but feels live
  }

  // -------------------------------------------------------
  // Globe integration
  // -------------------------------------------------------

  _notifyGlobe(alert) {
    window.dispatchEvent(new CustomEvent("veritas:breakingAlert", {
      detail: {
        lat:      alert.lat,
        lng:      alert.lng,
        severity: alert.severity,
        color:    alert.color
      }
    }))
  }

  // -------------------------------------------------------
  // Helpers
  // -------------------------------------------------------

  _escapeHtml(str) {
    if (!str) return ""
    return str
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
  }
}
