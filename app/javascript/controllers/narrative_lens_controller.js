import { Controller } from "@hotwired/stimulus"

const FLAGS = {
  "western_mainstream": "🌐",
  "us_liberal":         "🔵",
  "us_conservative":    "🔴",
  "china_state":        "🇨🇳",
  "russia_state":       "🇷🇺",
  "global_south":       "🌍"
}

export default class extends Controller {
  connect() {
    this._perspectiveHandler = (e) => this._onPerspectiveChange(e)
    window.addEventListener("veritas:perspectiveChange", this._perspectiveHandler)

    // Restore active perspective from localStorage on page load
    const saved = localStorage.getItem("veritas:perspective")
    if (saved && saved !== "all") {
      this._fetchContext(saved)
    }
  }

  disconnect() {
    window.removeEventListener("veritas:perspectiveChange", this._perspectiveHandler)
  }

  _onPerspectiveChange(event) {
    const slug = event.detail.slug
    if (!slug || slug === "all") {
      this._clear()
    } else {
      this._fetchContext(slug)
    }
  }

  async _fetchContext(slug) {
    this._setLoading(slug)
    try {
      const response = await fetch(`/api/perspective/${slug}/context`)
      if (!response.ok) throw new Error(`HTTP ${response.status}`)
      const data = await response.json()
      this._render(data)
    } catch (err) {
      console.error("[NarrativeLens] Failed to fetch context:", err)
      this._setError()
    }
  }

  _setLoading(slug) {
    const flag = FLAGS[slug] || "◈"
    this.element.innerHTML = `
      <div class="vt-narrative-panel vt-narrative-panel--loading">
        <div class="vt-narrative-panel-header">
          <span class="vt-lens-flag">${flag}</span>
          <span class="vt-narrative-loading-text">ANALYZING PERSPECTIVE</span>
          <span class="vt-narrative-loading-dots">
            <span>.</span><span>.</span><span>.</span>
          </span>
        </div>
      </div>
    `
    this.element.classList.remove("d-none")
  }

  _setError() {
    this.element.innerHTML = `
      <div class="vt-narrative-panel vt-narrative-panel--error">
        <span class="vt-narrative-error">CONTEXT UNAVAILABLE</span>
      </div>
    `
  }

  _clear() {
    this.element.innerHTML = ""
    this.element.classList.add("d-none")
  }

  _render(data) {
    const div      = data.divergence || {}
    const score    = div.score ?? null
    const label    = div.label || ""
    const status   = div.status || ""
    const flag     = FLAGS[data.slug] || "◈"

    const scoreColor = { CRITICAL: "#ff3a5e", HIGH: "#f59e0b", MODERATE: "#22c55e", LOW: "#38bdf8" }[label] || "#38bdf8"

    const divergenceHtml = status === "insufficient_data"
      ? `<div class="vt-divergence-na">INSUFFICIENT DATA FOR DIVERGENCE SCORE</div>`
      : `<div class="vt-divergence-row">
          <span class="vt-divergence-label">NARRATIVE DIVERGENCE vs WESTERN MAINSTREAM</span>
          <span class="vt-divergence-score" style="color:${scoreColor}">${score ?? "—"}</span>
          <span class="vt-divergence-badge" style="color:${scoreColor};border-color:${scoreColor}40;">${label}</span>
        </div>
        <div class="vt-divergence-bar-track">
          <div class="vt-divergence-bar-fill" style="width:${score ?? 0}%;background:${scoreColor};"></div>
        </div>`

    const framesHtml = (data.frames || []).map(f => `
      <div class="vt-narrative-frame">
        <div class="vt-frame-meta">
          <span class="vt-frame-source">${f.source || "Unknown"}</span>
          ${f.sentiment ? `<span class="vt-frame-sentiment">${f.sentiment}</span>` : ""}
        </div>
        <div class="vt-frame-headline">${f.headline || ""}</div>
        ${f.summary ? `<div class="vt-frame-summary">${f.summary}</div>` : ""}
      </div>
    `).join("")

    const sourcesHtml = (data.sources || []).slice(0, 8).map(s =>
      `<span class="vt-source-chip">${s}</span>`
    ).join("")

    this.element.innerHTML = `
      <div class="vt-narrative-panel">
        <div class="vt-narrative-panel-header">
          <span class="vt-lens-flag">${flag}</span>
          <span class="vt-narrative-lens-name">${data.label || data.slug}</span>
          ${data.topic ? `<span class="vt-narrative-topic-tag">${data.topic.toUpperCase()}</span>` : ""}
        </div>

        ${divergenceHtml}

        ${framesHtml ? `
          <div class="vt-narrative-section-title">TOP NARRATIVE FRAMES</div>
          <div class="vt-narrative-frames">${framesHtml}</div>
        ` : ""}

        ${sourcesHtml ? `
          <div class="vt-narrative-section-title">MONITORED SOURCES</div>
          <div class="vt-narrative-sources">${sourcesHtml}</div>
        ` : ""}
      </div>
    `
    this.element.classList.remove("d-none")
  }
}
