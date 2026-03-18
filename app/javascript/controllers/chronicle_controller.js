import { Controller } from "@hotwired/stimulus"

export default class extends Controller {}

function rgba(hex, alpha) {
  if (!hex || !hex.startsWith("#") || hex.length !== 7) return hex

  const red = parseInt(hex.slice(1, 3), 16)
  const green = parseInt(hex.slice(3, 5), 16)
  const blue = parseInt(hex.slice(5, 7), 16)

  return `rgba(${red}, ${green}, ${blue}, ${alpha})`
}

function clamp(value, min, max) {
  return Math.min(Math.max(value, min), max)
}

function formatDelta(delta) {
  if (delta == null) return "N/A"
  const rounded = Math.round(delta)
  return rounded > 0 ? `↓${rounded} pts trust` : "no trust delta"
}

export class ChronicleMode {
  constructor(journeyController, route, globeController) {
    this._journey = journeyController
    this._route = route
    this._globeController = globeController
    this._globe = globeController.globe
    this._segments = [...(route.segments || [])].sort((left, right) => left.segmentIndex - right.segmentIndex)
    this._hops = route.hops || []
    this._activePerspective = this._journey.activePerspective

    this._currentIndex = 0
    this._auto = false
    this._paused = false
    this._autoIntervalSeconds = 4
    this._autoTimer = null
    this._holdTimer = null
    this._timeouts = []
    this._completionScheduled = false
  }

  start() {
    if (!this._globe || !this._hops.length) return

    this._mountHud()
    this._renderScene(0, { arrivalOnly: true })

    const currentView = this._globe.pointOfView?.() || { lat: this._hops[0].lat, lng: this._hops[0].lng, altitude: 2.5 }
    this._globe.pointOfView({
      lat: currentView.lat,
      lng: currentView.lng,
      altitude: (currentView.altitude || 2.5) + 0.5
    }, 900)

    const kickoff = window.setTimeout(() => this._playHop(0), 220)
    this._timeouts.push(kickoff)
  }

  destroy() {
    this._clearTimers()
    if (this._globe) this._globe.controls().autoRotate = false
  }

  syncHud() {
    if (!this._hud) return

    this._hud.querySelector("[data-chronicle-counter]").textContent = `${this._currentIndex + 1}/${this._hops.length}`
    this._hud.querySelector("[data-chronicle-auto-label]").textContent = this._auto ? `AUTO ${this._autoIntervalSeconds}s` : "AUTO"
    this._hud.querySelector("[data-chronicle-pause-label]").textContent = this._paused ? "RESUME" : "PAUSE"
    this._hud.querySelector("[data-chronicle-mute]").textContent = this._journey.muted ? "MUTE" : "AUDIO"

    this._hud.querySelectorAll("[data-hop-index]").forEach((button) => {
      const index = Number(button.dataset.hopIndex)
      button.classList.toggle("is-current", index === this._currentIndex)
      button.classList.toggle("is-visited", index < this._currentIndex)
    })
  }

  advance() {
    if (this._currentIndex >= this._hops.length - 1) return

    this._playHop(this._currentIndex + 1)
  }

  retreat() {
    if (this._currentIndex <= 0) return

    this._playHop(this._currentIndex - 1)
  }

  jumpTo(index) {
    const targetIndex = clamp(index, 0, this._hops.length - 1)
    this._playHop(targetIndex)
  }

  toggleAuto() {
    this._auto = !this._auto
    this._paused = false

    if (this._auto) {
      this._scheduleAuto()
    } else {
      this._clearAutoTimer()
    }

    this.syncHud()
  }

  togglePause() {
    this._paused = !this._paused

    if (this._paused) {
      this._clearAutoTimer()
    } else if (this._auto) {
      this._scheduleAuto()
    }

    this.syncHud()
  }

  armAutoCycle() {
    this.releaseAutoCycle()
    this._holdTimer = window.setTimeout(() => {
      const options = [3, 4, 6]
      const currentIndex = options.indexOf(this._autoIntervalSeconds)
      this._autoIntervalSeconds = options[(currentIndex + 1) % options.length]
      if (this._auto && !this._paused) this._scheduleAuto()
      this.syncHud()
    }, 450)
  }

  releaseAutoCycle() {
    if (this._holdTimer) clearTimeout(this._holdTimer)
    this._holdTimer = null
  }

  _playHop(index) {
    this._completionScheduled = false
    this._clearAutoTimer()
    this._clearTimeouts()

    this._currentIndex = index
    const hop = this._hops[index]
    this._journey.highlightSidebarArticle(hop?.articleId)
    this.syncHud()

    if (index === 0) {
      this._renderScene(index, { arrivalOnly: true })
      this._renderOriginPanel(hop)
    } else {
      this._renderScene(index, { arrivalOnly: false })
      this._renderTransitPanel(index)
    }

    if (this._auto && !this._paused && index < this._hops.length - 1) {
      this._scheduleAuto()
    }

    if (index === this._hops.length - 1) {
      this._scheduleCompletion()
    }
  }

  _renderScene(index, { arrivalOnly }) {
    const ghostColor = "rgba(140, 153, 173, 0.15)"
    const activeHop = this._hops[index]
    const previousHop = this._hops[index - 1]
    const activeSegmentIndex = index - 1

    const arcs = this._segments.map((segment, segmentIndex) => {
      if (segmentIndex > activeSegmentIndex) {
        return {
          ...segment,
          color: ghostColor,
          arcDashLength: 0.16,
          arcDashGap: 0.16,
          arcDashAnimateTime: 0,
          arcStroke: 0.75,
          _journey: true
        }
      }

      if (segmentIndex < activeSegmentIndex) {
        return {
          ...segment,
          color: rgba(segment.journeyColor || segment.color || "#00f0ff", 0.35),
          arcDashLength: 0.34,
          arcDashGap: 0.18,
          arcDashAnimateTime: 0,
          arcStroke: 1.25,
          _journey: true
        }
      }

      return {
        ...segment,
        color: segment.journeyColor || segment.color || "#00f0ff",
        arcDashLength: 0.46,
        arcDashGap: 0.12,
        arcDashAnimateTime: arrivalOnly ? 0 : 1500,
        arcStroke: 2.8,
        _journey: true
      }
    })

    const points = this._hops.map((hop, hopIndex) => {
      if (hopIndex === index) {
        return {
          lat: hop.lat,
          lng: hop.lng,
          size: 0.95,
          radius: 1.5,
          color: hopIndex === 0 ? "#ffffff" : (hop.journeyColor || hop.framingColor || "#ffffff"),
          _journey: true
        }
      }

      if (hopIndex < index) {
        return {
          lat: hop.lat,
          lng: hop.lng,
          size: 0.2,
          radius: 0.45,
          color: rgba(hop.journeyColor || hop.framingColor || "#00f0ff", 0.35),
          _journey: true
        }
      }

      return {
        lat: hop.lat,
        lng: hop.lng,
        size: 0.12,
        radius: 0.3,
        color: "rgba(140, 153, 173, 0.18)",
        _journey: true
      }
    })

    const rings = []
    if (activeHop) {
      rings.push({
        lat: activeHop.lat,
        lng: activeHop.lng,
        color: index === 0 ? "rgba(255,255,255,0.95)" : rgba(activeHop.framingColor || "#00f0ff", 0.9),
        maxRadius: index === 0 ? 16 : 8,
        propagationSpeed: 2.2,
        repeatPeriod: 2000
      })

      if (this._matchesPerspective(activeHop.perspectiveSlug) && this._activePerspective !== "all") {
        rings.push({
          lat: activeHop.lat,
          lng: activeHop.lng,
          color: rgba(activeHop.perspectiveColor || "#38bdf8", 0.45),
          maxRadius: 12,
          propagationSpeed: 1.4,
          repeatPeriod: 2200
        })
      }
    }

    this._globe
      .pointsData(points)
      .arcsData(arcs)
      .ringsData(rings)

    if (index === 0) {
      this._globe.pointOfView({ lat: activeHop.lat, lng: activeHop.lng, altitude: 1.8 }, 1200)
      return
    }

    const midpoint = {
      lat: (previousHop.lat + activeHop.lat) / 2,
      lng: (previousHop.lng + activeHop.lng) / 2
    }

    this._globe.pointOfView({ lat: midpoint.lat, lng: midpoint.lng, altitude: 2.2 }, 900)

    if (arrivalOnly) {
      this._globe.pointOfView({ lat: activeHop.lat, lng: activeHop.lng, altitude: 1.8 }, 1200)
      this._renderArrivalPanel(index)
      return
    }

    const arrivalTimeout = window.setTimeout(() => {
      this._globe.pointOfView({ lat: activeHop.lat, lng: activeHop.lng, altitude: 1.8 }, 1200)
      this._renderArrivalPanel(index)
      this._journey.playTone(440, 120, 0.15)
    }, 950)
    this._timeouts.push(arrivalTimeout)
  }

  _renderOriginPanel(hop) {
    if (!this._panel) return

    this._panel.innerHTML = `
      <div class="vt-chronicle-framing-chip" style="--chip-color:#22c55e;">
        <div class="vt-chronicle-chip-label">HOP 1/${this._hops.length} · ORIGIN · ${hop?.sourceName || "UNKNOWN"} · ${hop?.city || hop?.country || "UNKNOWN"} · ${this._journey.formatTime(hop?.publishedAt)}</div>
        <div class="vt-chronicle-chip-value">FRAMING: ${hop?.framingLabel || "ORIGINAL"}</div>
        <div class="vt-chronicle-chip-headline">${hop?.headline || "No headline available"}</div>
      </div>
    `
  }

  _renderTransitPanel(index) {
    if (!this._panel) return

    const sourceHop = this._hops[index - 1]
    const targetHop = this._hops[index]

    this._panel.innerHTML = `
      <div class="vt-chronicle-framing-chip" style="--chip-color:${targetHop?.journeyColor || targetHop?.framingColor || "#f59e0b"};">
        <div class="vt-chronicle-chip-label">TRANSIT ${index}/${this._segments.length}</div>
        <div class="vt-chronicle-chip-value">${sourceHop?.framingLabel || "ORIGINAL"} → ...</div>
        <div class="vt-chronicle-chip-headline">${targetHop?.headline || "No headline available"}</div>
      </div>
    `
  }

  _renderArrivalPanel(index) {
    if (!this._panel) return

    const sourceHop = this._hops[index - 1]
    const targetHop = this._hops[index]
    const segment = this._segments[index - 1]
    const trustDelta = (sourceHop?.trustScore ?? 0) - (targetHop?.trustScore ?? 0)
    const perspectiveTag = targetHop?.perspectiveSlug && targetHop.perspectiveSlug !== "unclassified"
      ? `<span class="vt-chronicle-perspective-tag" style="--tag-color:${targetHop.perspectiveColor || "#64748b"};">${targetHop.perspectiveTag}</span>`
      : ""

    this._panel.innerHTML = `
      <div class="vt-chronicle-delta" style="--delta-color:${targetHop?.journeyColor || targetHop?.framingColor || "#f59e0b"};">
        <div class="vt-chronicle-delta-header">
          <div>
            <div class="vt-chronicle-delta-title">${sourceHop?.framingLabel || "ORIGINAL"} → ${targetHop?.framingLabel || "AMPLIFIED"}</div>
            <div class="vt-chronicle-delta-subtitle">HOP ${index + 1}/${this._hops.length} · ${targetHop?.sourceName || "UNKNOWN"} · ${targetHop?.city || targetHop?.country || "UNKNOWN"}</div>
          </div>
          ${perspectiveTag}
        </div>
        <div class="vt-chronicle-delta-row"><span>SENTIMENT</span><strong>${sourceHop?.sentimentLabel || "NEUTRAL"} → ${targetHop?.sentimentLabel || "NEUTRAL"} (${formatDelta(trustDelta)})</strong></div>
        <div class="vt-chronicle-delta-row"><span>HEADLINE</span><strong>${targetHop?.headline || "No headline available"}</strong></div>
        <div class="vt-chronicle-delta-row"><span>SOURCE</span><strong>${targetHop?.sourceName || "UNKNOWN"} · ${targetHop?.city || targetHop?.country || "UNKNOWN"} · +${this._journey.formatDuration(this._secondsFromOrigin(targetHop))} since origin</strong></div>
        <div class="vt-chronicle-delta-row"><span>MATCH</span><strong>${segment?.semanticSimilarity || 0}% semantic similarity</strong></div>
      </div>
    `
  }

  _scheduleAuto() {
    this._clearAutoTimer()
    if (!this._auto || this._paused) return

    this._autoTimer = window.setTimeout(() => this.advance(), this._autoIntervalSeconds * 1000)
  }

  _scheduleCompletion() {
    if (this._completionScheduled) return
    this._completionScheduled = true

    const timeoutId = window.setTimeout(() => {
      this._globe.pointOfView({
        lat: this._hops[0].lat,
        lng: this._hops[0].lng,
        altitude: 3.0
      }, 1200)
      this._journey.showSummary()
    }, 1800)
    this._timeouts.push(timeoutId)
  }

  _clearAutoTimer() {
    if (this._autoTimer) clearTimeout(this._autoTimer)
    this._autoTimer = null
  }

  _clearTimeouts() {
    this._timeouts.forEach((timeoutId) => clearTimeout(timeoutId))
    this._timeouts = []
  }

  _clearTimers() {
    this._clearAutoTimer()
    this._clearTimeouts()
    this.releaseAutoCycle()
  }

  _mountHud() {
    const dots = this._hops.map((hop, index) => `
      <button class="vt-chronicle-dot" type="button" data-hop-index="${index}" data-action="click->journey#chronicleJump" title="${hop.sourceName || "Hop"}"></button>
    `).join("")

    const hud = document.createElement("div")
    hud.className = "vt-journey-hud vt-chronicle-hud"
    hud.innerHTML = `
      <div class="vt-chronicle-panel" data-chronicle-panel></div>
      <div class="vt-chronicle-bar">
        <div class="vt-chronicle-title">
          NARRATIVE CHRONICLE <span data-chronicle-counter>1/${this._hops.length}</span> | ${this._route.routeName || "Route"}
        </div>
        <div class="vt-chronicle-controls">
          <button class="vt-journey-icon-btn" type="button" data-action="click->journey#chroniclePrev">PREV</button>
          <button class="vt-journey-icon-btn" type="button" data-action="click->journey#chronicleNext">NEXT</button>
          <button class="vt-journey-icon-btn" type="button"
                  data-action="click->journey#chronicleAuto mousedown->journey#armChronicleAutoCycle mouseup->journey#releaseChronicleAutoCycle mouseleave->journey#releaseChronicleAutoCycle touchstart->journey#armChronicleAutoCycle touchend->journey#releaseChronicleAutoCycle">
            <span data-chronicle-auto-label>AUTO</span>
          </button>
          <button class="vt-journey-icon-btn" type="button" data-action="click->journey#chroniclePause">
            <span data-chronicle-pause-label>PAUSE</span>
          </button>
          <button class="vt-journey-icon-btn" type="button" data-chronicle-mute data-action="click->journey#toggleMute"></button>
          <button class="vt-journey-icon-btn" type="button" data-action="click->journey#exit">EXIT</button>
        </div>
        <div class="vt-chronicle-dots">${dots}</div>
      </div>
    `

    this._journey.mountHud(hud)
    this._hud = hud
    this._panel = hud.querySelector("[data-chronicle-panel]")
    this.syncHud()
  }

  _matchesPerspective(slug) {
    return this._activePerspective === "all" || slug === this._activePerspective
  }

  _secondsFromOrigin(hop) {
    const originTime = this._hops[0]?.publishedAt ? Date.parse(this._hops[0].publishedAt) : null
    const hopTime = hop?.publishedAt ? Date.parse(hop.publishedAt) : null
    if (!originTime || !hopTime) return hop?.delaySeconds || 0

    return Math.max(0, Math.round((hopTime - originTime) / 1000))
  }
}
