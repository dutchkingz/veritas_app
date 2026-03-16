import { Controller } from "@hotwired/stimulus"

// TribunalController
//
// War Room Intelligence Tribunal — three AI agents debate live.
// Listens for veritas:openTribunal events, fetches /api/tribunal/:id,
// then runs a sequential typewriter sequence: Analyst → Sentinel → Arbiter.
// Each agent types in at a measured pace, cursor blinking, then passes
// the floor to the next. Verdict bar slides up when the tribunal concludes.

const TYPING_SPEED = {
  analyst:  20,  // ms per character
  sentinel: 20,
  arbiter:  26   // deliberate — adds weight to the verdict
}

const INTER_AGENT_DELAY = 700 // ms pause between agents

export default class extends Controller {
  connect() {
    this._openHandler = (e) => this._onOpen(e)
    window.addEventListener("veritas:openTribunal", this._openHandler)
    this._intervals = []
    this._timeouts  = []
  }

  disconnect() {
    window.removeEventListener("veritas:openTribunal", this._openHandler)
    this._cleanup()
  }

  // -------------------------------------------------------
  // Private
  // -------------------------------------------------------

  async _onOpen(event) {
    const { articleId } = event.detail
    if (!articleId) return

    this._cleanup()
    this._renderLoading()

    try {
      const response = await fetch(`/api/tribunal/${articleId}`)
      if (!response.ok) throw new Error(`HTTP ${response.status}`)
      const data = await response.json()

      if (data.status === "not_ready") {
        this._renderNotReady(data)
      } else {
        this._renderTribunal(data)
      }
    } catch (err) {
      console.error("[Tribunal] Failed to load:", err)
      this._renderError()
    }
  }

  // -------------------------------------------------------
  // Panel lifecycle
  // -------------------------------------------------------

  _renderLoading() {
    this._createBackdrop(`
      <div class="tribunal-header">
        <div class="tribunal-header-left">
          <div class="tribunal-title">INTELLIGENCE_TRIBUNAL</div>
          <div class="tribunal-subtitle">VERITAS TRIAD ANALYSIS</div>
        </div>
        <button class="tribunal-close" aria-label="Close">✕</button>
      </div>
      <div class="tribunal-state">
        <div class="tribunal-spinner"></div>
        <div class="tribunal-state-title">Summoning the Triad</div>
        <div class="tribunal-state-sub">Retrieving agent intelligence...</div>
      </div>
    `)
  }

  _renderError() {
    this._createBackdrop(`
      <div class="tribunal-header">
        <div class="tribunal-header-left">
          <div class="tribunal-title">INTELLIGENCE_TRIBUNAL</div>
        </div>
        <button class="tribunal-close" aria-label="Close">✕</button>
      </div>
      <div class="tribunal-state">
        <div class="tribunal-state-icon">◈</div>
        <div class="tribunal-state-title">Tribunal Unavailable</div>
        <div class="tribunal-state-sub">Failed to retrieve agent data.<br>Check server logs.</div>
      </div>
    `)
  }

  _renderNotReady(data) {
    const status = (data.analysis_status || "pending").toUpperCase()
    this._createBackdrop(`
      <div class="tribunal-header">
        <div class="tribunal-header-left">
          <div class="tribunal-title">INTELLIGENCE_TRIBUNAL</div>
          <div class="tribunal-subtitle">VERITAS TRIAD ANALYSIS</div>
        </div>
        <button class="tribunal-close" aria-label="Close">✕</button>
      </div>
      <div class="tribunal-state">
        <div class="tribunal-state-icon">⬡</div>
        <div class="tribunal-state-title">Triad Analysis ${status}</div>
        <div class="tribunal-state-sub">
          The three agents have not yet completed<br>their analysis of this signal.
        </div>
      </div>
    `)
  }

  _renderTribunal(data) {
    const { article, turns } = data

    const turnsHTML = turns.map((turn, i) => `
      <div class="tribunal-turn" id="tribunal-turn-${i}" data-agent="${turn.agent}">
        <div class="tribunal-agent-meta">
          <div class="tribunal-agent-icon"
               style="color:${turn.color};border-color:${this._alpha(turn.color, 0.3)};">
            ${turn.icon}
          </div>
          <div class="tribunal-agent-name" style="color:${turn.color};">${turn.name}</div>
          <div class="tribunal-agent-model">${turn.model}</div>
        </div>
        <div class="tribunal-message">
          <span class="tribunal-message-text" id="tribunal-msg-${i}"></span>
        </div>
      </div>
    `).join("")

    this._createBackdrop(`
      <div class="tribunal-header">
        <div class="tribunal-header-left">
          <div class="tribunal-title">INTELLIGENCE_TRIBUNAL</div>
          <div class="tribunal-subtitle">VERITAS TRIAD ANALYSIS</div>
        </div>
        <button class="tribunal-close" aria-label="Close">✕</button>
      </div>

      <div class="tribunal-article-bar">
        <div class="tribunal-article-headline">${this._esc(article.headline)}</div>
        <div class="tribunal-article-meta">
          <span>${this._esc(article.source)}</span>
          <span class="tribunal-threat-badge"
                style="color:${article.threat_color};border-color:${this._alpha(article.threat_color, 0.35)};">
            ${article.threat_level}
          </span>
        </div>
      </div>

      <div class="tribunal-turns-container">
        ${turnsHTML}
      </div>

      <div class="tribunal-verdict" id="tribunal-verdict">
        <div class="tribunal-verdict-trust">
          <span class="tribunal-verdict-score">${article.trust_score}</span>
          <span class="tribunal-verdict-label">TRUST SCORE</span>
        </div>
        <div class="tribunal-verdict-divider"></div>
        <div class="tribunal-verdict-text">
          <span class="tribunal-verdict-heading">TRIBUNAL COMPLETE</span>
          <span class="tribunal-verdict-sub">Triad consensus achieved. Intelligence verified.</span>
        </div>
      </div>
    `)

    // Start the sequential agent reveal
    requestAnimationFrame(() => this._runSequence(turns))
  }

  _createBackdrop(innerHTML) {
    const backdrop = document.createElement("div")
    backdrop.id = "tribunal-backdrop"
    backdrop.className = "tribunal-backdrop"

    const panel = document.createElement("div")
    panel.id = "tribunal-panel"
    panel.className = "tribunal-panel"
    panel.innerHTML = innerHTML

    backdrop.appendChild(panel)
    document.body.appendChild(backdrop)

    // Close on backdrop click (outside panel)
    backdrop.addEventListener("click", (e) => {
      if (e.target === backdrop) this._cleanup()
    })

    panel.querySelector(".tribunal-close")?.addEventListener("click", () => this._cleanup())
  }

  // -------------------------------------------------------
  // Typewriter sequence
  // -------------------------------------------------------

  _runSequence(turns) {
    let cumulativeDelay = 500 // initial pause before first agent

    turns.forEach((turn, index) => {
      const startDelay = cumulativeDelay

      this._timeouts.push(setTimeout(() => {
        this._revealTurn(turn, index)
      }, startDelay))

      // Next agent starts after this one finishes typing + inter-agent pause
      cumulativeDelay += (turn.message.length * TYPING_SPEED[turn.agent]) + INTER_AGENT_DELAY
    })

    // Verdict bar appears after all agents are done
    const verdictDelay = cumulativeDelay + 400
    this._timeouts.push(setTimeout(() => {
      document.getElementById("tribunal-verdict")?.classList.add("tribunal-verdict--visible")
    }, verdictDelay))
  }

  _revealTurn(turn, index) {
    const container = document.getElementById(`tribunal-turn-${index}`)
    const msgEl     = document.getElementById(`tribunal-msg-${index}`)
    if (!container || !msgEl) return

    container.classList.add("tribunal-turn--visible")

    // Scroll the new turn into view
    container.scrollIntoView({ behavior: "smooth", block: "nearest" })

    this._typewrite(msgEl, turn.message, TYPING_SPEED[turn.agent] || 22)
  }

  _typewrite(el, text, speed) {
    if (!el || !text) return

    el.textContent = ""

    // Insert blinking cursor after the message element
    const cursor = document.createElement("span")
    cursor.className = "tribunal-cursor"
    cursor.textContent = "▌"
    el.insertAdjacentElement("afterend", cursor)

    let i = 0
    const interval = setInterval(() => {
      el.textContent += text[i]
      i++
      if (i >= text.length) {
        clearInterval(interval)
        cursor.remove()
        this._intervals = this._intervals.filter(iv => iv !== interval)
      }
    }, speed)

    this._intervals.push(interval)
  }

  // -------------------------------------------------------
  // Cleanup
  // -------------------------------------------------------

  _cleanup() {
    this._intervals.forEach(clearInterval)
    this._timeouts.forEach(clearTimeout)
    this._intervals = []
    this._timeouts  = []

    const backdrop = document.getElementById("tribunal-backdrop")
    if (backdrop) {
      backdrop.classList.add("tribunal-backdrop--closing")
      setTimeout(() => backdrop.remove(), 260)
    }
  }

  // -------------------------------------------------------
  // Helpers
  // -------------------------------------------------------

  _esc(str) {
    if (!str) return ""
    return str
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
  }

  // Hex color with opacity (returns rgba string)
  _alpha(hex, opacity) {
    if (!hex || !hex.startsWith("#")) return `rgba(100,100,100,${opacity})`
    const h = hex.slice(1)
    const r = parseInt(h.slice(0, 2), 16)
    const g = parseInt(h.slice(2, 4), 16)
    const b = parseInt(h.slice(4, 6), 16)
    return `rgba(${r},${g},${b},${opacity})`
  }
}
