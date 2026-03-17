import { Controller } from "@hotwired/stimulus"

// ─────────────────────────────────────────────────────────────────────────────
// VERITAS VOICE ORB
// Cinemati push-to-talk intelligence interface.
// States: idle → listening → processing → speaking → idle
// Tech: Canvas 2D particle orb + Web Speech API (STT + TTS)
// ─────────────────────────────────────────────────────────────────────────────

const STATE = { IDLE: "idle", LISTENING: "listening", PROCESSING: "processing", SPEAKING: "speaking" }

const COLOR = {
  idle:       { core: "rgba(0,212,255,0.9)",   glow: "rgba(0,212,255,0.15)",  ring: "rgba(0,212,255,0.08)"  },
  listening:  { core: "rgba(0,212,255,1)",      glow: "rgba(0,212,255,0.35)",  ring: "rgba(0,212,255,0.2)"   },
  processing: { core: "rgba(255,196,7,0.95)",   glow: "rgba(255,196,7,0.25)",  ring: "rgba(255,196,7,0.15)"  },
  speaking:   { core: "rgba(0,255,135,0.95)",   glow: "rgba(0,255,135,0.25)",  ring: "rgba(0,255,135,0.15)"  }
}

export default class extends Controller {
  static targets = [
    "canvas", "label",
    "briefingOverlay", "briefingQuery", "briefingText", "briefingConfidence",
    "fallbackWrap", "fallbackInput"
  ]
  static values = { chatUrl: String }

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  connect() {
    this.state      = STATE.IDLE
    this.particles  = []
    this.raf        = null
    this.transcript = ""
    this.dismissTimer = null

    this._initParticles()
    this._startRenderLoop()
    this._setupSpeechRecognition()
  }

  disconnect() {
    if (this.raf) cancelAnimationFrame(this.raf)
    if (this.recognition) this.recognition.abort()
    if (this.synth) this.synth.cancel()
    clearTimeout(this.dismissTimer)
  }

  // ── User actions ───────────────────────────────────────────────────────────

  toggle() {
    if (this.state === STATE.IDLE) {
      this._startListening()
    } else if (this.state === STATE.LISTENING) {
      this._stopListening()
    } else if (this.state === STATE.SPEAKING) {
      this._stopSpeaking()
    }
    // processing state: click is a no-op (wait for result)
  }

  dismissBriefing() {
    this.briefingOverlayTarget.classList.add("d-none")
    clearTimeout(this.dismissTimer)
  }

  submitFallback() {
    const query = this.fallbackInputTarget.value.trim()
    if (!query) return
    this.fallbackWrapTarget.classList.add("d-none")
    this.fallbackInputTarget.value = ""
    this.transcript = query
    this._setState(STATE.PROCESSING)
    this._sendQuery(query)
  }

  // ── Speech Recognition ────────────────────────────────────────────────────

  _setupSpeechRecognition() {
    const SR = window.SpeechRecognition || window.webkitSpeechRecognition
    if (!SR) {
      // No native support — orb click will show text fallback instead
      this._hasSpeechRecognition = false
      return
    }

    this._hasSpeechRecognition = true
    this.recognition = new SR()
    this.recognition.lang           = "en-US"
    this.recognition.continuous     = false
    this.recognition.interimResults = true
    this.recognition.maxAlternatives = 1

    this.recognition.onresult = (event) => {
      const result = event.results[event.results.length - 1]
      this.transcript = result[0].transcript
    }

    this.recognition.onend = () => {
      if (this.state !== STATE.LISTENING) return
      if (this.transcript.trim()) {
        this._setState(STATE.PROCESSING)
        this._sendQuery(this.transcript.trim())
      } else {
        this._setState(STATE.IDLE)
      }
    }

    this.recognition.onerror = (event) => {
      if (event.error === "not-allowed" || event.error === "service-not-allowed") {
        console.warn("[VERITAS Voice] Microphone permission denied — falling back to text input")
        this._showFallback()
      }
      this._setState(STATE.IDLE)
    }
  }

  _startListening() {
    if (!this._hasSpeechRecognition) {
      this._showFallback()
      return
    }
    this.transcript = ""
    try {
      this.recognition.start()
      this._setState(STATE.LISTENING)
    } catch (e) {
      // recognition already started — ignore
    }
  }

  _stopListening() {
    try {
      this.recognition.stop()
    } catch (e) { /* ignore */ }
    // onend fires automatically → sends query
  }

  _showFallback() {
    this.fallbackWrapTarget.classList.remove("d-none")
    this.fallbackInputTarget.focus()
  }

  // ── Query + RAG ───────────────────────────────────────────────────────────

  async _sendQuery(query) {
    // 1. Dispatch globe search event immediately — globe starts filtering
    document.dispatchEvent(new CustomEvent("veritas:search", {
      detail: { query, source: "voice" }
    }))

    // 2. Get CSRF token
    const csrf = document.querySelector('meta[name="csrf-token"]')?.content

    try {
      const response = await fetch(this.chatUrlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": csrf
        },
        body: JSON.stringify({
          message: query,
          format_mode: "voice_briefing"
        })
      })

      if (!response.ok) throw new Error(`HTTP ${response.status}`)

      const data = await response.json()
      this._showBriefing(query, data)
      this._speak(data.response)
    } catch (err) {
      console.error("[VERITAS Voice] Query failed:", err)
      this._setState(STATE.IDLE)
    }
  }

  // ── Text-to-Speech ────────────────────────────────────────────────────────

  _speak(text) {
    if (!("speechSynthesis" in window)) {
      this._setState(STATE.IDLE)
      return
    }

    this.synth = window.speechSynthesis
    this.synth.cancel()

    const utterance = new SpeechSynthesisUtterance(text)
    utterance.rate   = 0.95
    utterance.pitch  = 0.9
    utterance.volume = 1.0

    // Prefer a deeper, English voice
    const voices = this.synth.getVoices()
    const preferred = voices.find(v =>
      /en-US|en-GB/i.test(v.lang) && /google|microsoft|neural|natural/i.test(v.name)
    ) || voices.find(v => /en/i.test(v.lang))
    if (preferred) utterance.voice = preferred

    utterance.onstart = () => this._setState(STATE.SPEAKING)

    utterance.onboundary = (event) => {
      // Pulse orb on each word boundary
      if (event.name === "word") this._triggerPulse()
    }

    utterance.onend = () => {
      this._setState(STATE.IDLE)
      // Auto-dismiss briefing after 12 seconds
      this.dismissTimer = setTimeout(() => this.dismissBriefing(), 12000)
    }

    utterance.onerror = () => this._setState(STATE.IDLE)

    this._setState(STATE.SPEAKING)
    this.synth.speak(utterance)
  }

  _stopSpeaking() {
    if (this.synth) this.synth.cancel()
    this._setState(STATE.IDLE)
  }

  // ── Briefing Card ─────────────────────────────────────────────────────────

  _showBriefing(query, data) {
    this.briefingQueryTarget.textContent = `"${query}"`
    this.briefingTextTarget.textContent  = data.response || "No intelligence available."

    const conf     = (data.confidence || "").toUpperCase()
    const confEl   = this.briefingConfidenceTarget
    confEl.textContent = conf ? `CONFIDENCE: ${conf}` : ""
    confEl.className   = `voice-briefing-confidence confidence-${conf.toLowerCase()}`

    this.briefingOverlayTarget.classList.remove("d-none")
    clearTimeout(this.dismissTimer)
  }

  // ── State Machine ─────────────────────────────────────────────────────────

  _setState(newState) {
    this.state = newState
    this.canvasTarget.dataset.state = newState
    this.labelTarget.dataset.state  = newState
    this._updateLabel(newState)
  }

  _updateLabel(state) {
    const labels = {
      idle:       "VERITAS VOICE",
      listening:  "LISTENING...",
      processing: "PROCESSING...",
      speaking:   "SPEAKING..."
    }
    this.labelTarget.textContent = labels[state] || "VERITAS VOICE"
  }

  // ── Particle System (Canvas 2D) ────────────────────────────────────────────

  _initParticles() {
    const count = 120
    this.particles = []

    for (let i = 0; i < count; i++) {
      const angle      = Math.random() * Math.PI * 2
      const baseRadius = 18 + Math.random() * 14  // 18-32px from center
      this.particles.push({
        angle,
        radius:     baseRadius,
        baseRadius,
        speed:      (0.004 + Math.random() * 0.006) * (Math.random() < 0.5 ? 1 : -1),
        size:       0.6 + Math.random() * 1.2,
        opacity:    0.3 + Math.random() * 0.6,
        pulsePhase: Math.random() * Math.PI * 2,
        pulseSpeed: 0.03 + Math.random() * 0.04
      })
    }

    this._pulse    = 0      // speaking pulse intensity (0–1)
    this._pulseDir = -1
  }

  _triggerPulse() {
    this._pulse = 1.0
  }

  _startRenderLoop() {
    const canvas = this.canvasTarget
    const ctx    = canvas.getContext("2d")
    const cx     = canvas.width  / 2
    const cy     = canvas.height / 2

    let lastFrame = 0

    const render = (ts) => {
      this.raf = requestAnimationFrame(render)

      // Throttle to ~40fps when idle to save CPU
      const targetFps = this.state === STATE.IDLE ? 40 : 60
      if (ts - lastFrame < 1000 / targetFps) return
      lastFrame = ts

      ctx.clearRect(0, 0, canvas.width, canvas.height)

      const col     = COLOR[this.state]
      const isLive  = this.state !== STATE.IDLE
      const speedMul = this.state === STATE.PROCESSING ? 3.5 : 1.0
      const radiusMul = this.state === STATE.LISTENING  ? 1.45
                      : this.state === STATE.SPEAKING   ? 1.2 + this._pulse * 0.3
                      : 1.0

      // Draw ambient glow ring
      const grad = ctx.createRadialGradient(cx, cy, 0, cx, cy, 38 * radiusMul)
      grad.addColorStop(0, col.glow)
      grad.addColorStop(1, "rgba(0,0,0,0)")
      ctx.beginPath()
      ctx.arc(cx, cy, 38 * radiusMul, 0, Math.PI * 2)
      ctx.fillStyle = grad
      ctx.fill()

      // Draw outer ring (listening/speaking only)
      if (isLive) {
        ctx.beginPath()
        ctx.arc(cx, cy, 36 * radiusMul, 0, Math.PI * 2)
        ctx.strokeStyle = col.ring
        ctx.lineWidth   = 1
        ctx.stroke()
      }

      // Update and draw particles
      this.particles.forEach(p => {
        p.angle      += p.speed * speedMul
        p.pulsePhase += p.pulseSpeed
        const pulseDelta = Math.sin(p.pulsePhase) * (isLive ? 4 : 1.5)
        const r = p.baseRadius * radiusMul + pulseDelta

        const x = cx + Math.cos(p.angle) * r
        const y = cy + Math.sin(p.angle) * r

        const alpha = p.opacity * (isLive ? 0.9 : 0.55)

        ctx.beginPath()
        ctx.arc(x, y, p.size, 0, Math.PI * 2)
        ctx.fillStyle = col.core.replace(/[\d.]+\)$/, `${alpha})`)
        ctx.fill()
      })

      // Draw solid core dot
      ctx.beginPath()
      ctx.arc(cx, cy, isLive ? 5 : 3.5, 0, Math.PI * 2)
      ctx.fillStyle = col.core
      ctx.fill()

      // Decay speaking pulse
      if (this._pulse > 0) {
        this._pulse = Math.max(0, this._pulse - 0.06)
      }
    }

    this.raf = requestAnimationFrame(render)
  }
}
