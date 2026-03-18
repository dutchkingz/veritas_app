import { Controller } from "@hotwired/stimulus"

// ─── VERITAS War Room Screensaver ─────────────────────────────
// Easter-egg: WarGames (1983) NORAD command center screensaver.
// Triggered globally via Cmd+. — ESC or click to dismiss.
// ──────────────────────────────────────────────────────────────

const DEFCON_LEVELS = [
  { level: 5, label: "FADE OUT",     color: "#22c55e" },
  { level: 4, label: "DOUBLE TAKE",  color: "#38bdf8" },
  { level: 3, label: "ROUND HOUSE",  color: "#eab308" },
  { level: 2, label: "FAST PACE",    color: "#f97316" },
  { level: 1, label: "COCKED PISTOL", color: "#ff3a5e" },
]

const CONSOLE_LINES = [
  "GREETINGS PROFESSOR FALKEN.",
  "SHALL WE PLAY A GAME?",
  "",
  "LOGON: 00:00:00.00 GMT",
  "WOPR ONLINE /// ACTIVE DEFENSE NETWORK",
  "TRACKING GLOBAL NARRATIVE TRAJECTORIES...",
  "MONITORING 147 ACTIVE INFORMATION VECTORS",
  "CROSSREF: MEDIA BIAS INDEX — 23 ANOMALIES FLAGGED",
  "SIGNAL INTERCEPT: COORDINATED AMPLIFICATION DETECTED",
  "SOURCE CREDIBILITY MATRIX: 3 DOWNGRADES PENDING",
  "NARRATIVE ARC DIVERGENCE: EXCEEDS BASELINE BY 4.7 SIGMA",
  "VERITAS DEFENSE CONDITION: ELEVATED",
  "ALL SYSTEMS NOMINAL.",
  "",
  "A STRANGE GAME.",
  "THE ONLY WINNING MOVE IS NOT TO LIE.",
]

export default class extends Controller {
  connect() {
    this._keyHandler = (e) => this._onKey(e)
    document.addEventListener("keydown", this._keyHandler)
  }

  disconnect() {
    document.removeEventListener("keydown", this._keyHandler)
    this._close()
  }

  // ── Shortcut detection: Cmd+. ──

  _onKey(e) {
    // Cmd+. (Mac) or Ctrl+. (Win/Linux)
    if ((e.metaKey || e.ctrlKey) && e.key === ".") {
      e.preventDefault()
      e.stopPropagation()
      if (this._backdrop) { this._close() } else { this._launch() }
      return
    }
    // ESC to close
    if (e.key === "Escape" && this._backdrop) {
      this._close()
    }
  }

  // ── Launch screensaver ──

  _launch() {
    if (this._backdrop) return

    this._backdrop = document.createElement("div")
    this._backdrop.className = "screensaver-backdrop"
    this._backdrop.addEventListener("click", () => this._close())

    // Build the image path from the asset pipeline
    const imgEl = document.createElement("img")
    imgEl.className = "screensaver-image"
    imgEl.src = this.element.dataset.screensaverImage || "/assets/warroom_screensaver.png"
    imgEl.alt = "NORAD War Room"

    // Scanline overlay
    const scanlines = document.createElement("div")
    scanlines.className = "screensaver-scanlines"

    // HUD overlay
    const hud = document.createElement("div")
    hud.className = "screensaver-hud"
    hud.innerHTML = `
      <div class="screensaver-top-bar">
        <div class="screensaver-defcon">
          <span class="screensaver-defcon-label">DEFCON</span>
          <span class="screensaver-defcon-value" data-defcon-value>3</span>
        </div>
        <div class="screensaver-clock" data-clock></div>
        <div class="screensaver-status">
          <span class="screensaver-status-dot"></span>
          <span>WOPR ACTIVE</span>
        </div>
      </div>
      <div class="screensaver-console" data-console></div>
      <div class="screensaver-bottom-bar">
        <span>VERITAS INTELLIGENCE NETWORK // PRESS ESC TO RETURN</span>
      </div>
    `

    this._backdrop.appendChild(imgEl)
    this._backdrop.appendChild(scanlines)
    this._backdrop.appendChild(hud)
    document.body.appendChild(this._backdrop)

    // Cache DOM refs
    this._clockEl   = hud.querySelector("[data-clock]")
    this._consoleEl = hud.querySelector("[data-console]")
    this._defconEl  = hud.querySelector("[data-defcon-value]")

    // Start effects
    this._running = true
    this._startClock()
    this._startConsole()
    this._startDefconCycle()
  }

  // ── Close ──

  _close() {
    this._running = false
    if (this._clockInterval) clearInterval(this._clockInterval)
    if (this._consoleTimeout) clearTimeout(this._consoleTimeout)
    if (this._defconTimeout) clearTimeout(this._defconTimeout)

    if (this._backdrop) {
      this._backdrop.classList.add("screensaver-backdrop--closing")
      setTimeout(() => { this._backdrop?.remove(); this._backdrop = null }, 300)
    }
  }

  // ── Live clock (GMT) ──

  _startClock() {
    const tick = () => {
      if (!this._clockEl) return
      const now = new Date()
      const h = String(now.getUTCHours()).padStart(2, "0")
      const m = String(now.getUTCMinutes()).padStart(2, "0")
      const s = String(now.getUTCSeconds()).padStart(2, "0")
      this._clockEl.textContent = `${h}:${m}:${s} GMT`
    }
    tick()
    this._clockInterval = setInterval(tick, 1000)
  }

  // ── Console typewriter ──

  _startConsole() {
    let lineIdx = 0
    let charIdx = 0
    let currentLine = ""
    this._consoleEl.innerHTML = ""

    const type = () => {
      if (!this._running) return

      if (lineIdx >= CONSOLE_LINES.length) {
        // Loop back after a pause
        this._consoleTimeout = setTimeout(() => {
          if (!this._running) return
          this._consoleEl.innerHTML = ""
          lineIdx = 0
          charIdx = 0
          currentLine = ""
          type()
        }, 4000)
        return
      }

      const line = CONSOLE_LINES[lineIdx]

      if (charIdx <= line.length) {
        currentLine = line.substring(0, charIdx)
        this._updateConsole(lineIdx, currentLine, charIdx < line.length)
        charIdx++
        this._consoleTimeout = setTimeout(type, 25 + Math.random() * 20)
      } else {
        lineIdx++
        charIdx = 0
        currentLine = ""
        this._consoleTimeout = setTimeout(type, 300)
      }
    }

    this._consoleTimeout = setTimeout(type, 1000)
  }

  _updateConsole(lineIdx, currentText, typing) {
    // Keep last ~12 lines visible
    const lines = this._consoleEl.querySelectorAll(".screensaver-console-line")
    if (lines.length > lineIdx) {
      const last = lines[lines.length - 1]
      last.innerHTML = `<span class="screensaver-prompt">&gt;</span> ${currentText}${typing ? '<span class="screensaver-cursor">█</span>' : ""}`
    } else {
      const div = document.createElement("div")
      div.className = "screensaver-console-line"
      div.innerHTML = `<span class="screensaver-prompt">&gt;</span> ${currentText}${typing ? '<span class="screensaver-cursor">█</span>' : ""}`
      this._consoleEl.appendChild(div)

      // Remove oldest lines if too many
      while (this._consoleEl.children.length > 12) {
        this._consoleEl.removeChild(this._consoleEl.firstChild)
      }
    }
  }

  // ── DEFCON cycle ──

  _startDefconCycle() {
    let idx = 2 // Start at DEFCON 3
    const cycle = () => {
      if (!this._running || !this._defconEl) return
      const def = DEFCON_LEVELS[idx]
      this._defconEl.textContent = def.level
      this._defconEl.style.color = def.color
      this._defconEl.style.textShadow = `0 0 12px ${def.color}`

      // Slowly oscillate between 2-4
      idx = 1 + Math.floor(Math.random() * 3) // index 1-3 = DEFCON 4-2
      this._defconTimeout = setTimeout(cycle, 6000 + Math.random() * 8000)
    }
    cycle()
  }

}
