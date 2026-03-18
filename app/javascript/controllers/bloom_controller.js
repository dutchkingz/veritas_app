import { Controller } from "@hotwired/stimulus"

const BASE_PLAYBACK_MS = 15000

export default class extends Controller {}

function clamp(value, min, max) {
  return Math.min(Math.max(value, min), max)
}

function rgba(hex, alpha) {
  if (!hex || !hex.startsWith("#") || hex.length !== 7) return hex

  const red = parseInt(hex.slice(1, 3), 16)
  const green = parseInt(hex.slice(3, 5), 16)
  const blue = parseInt(hex.slice(5, 7), 16)

  return `rgba(${red}, ${green}, ${blue}, ${alpha})`
}

function formatDelay(seconds) {
  const total = Math.max(0, Math.round(seconds || 0))
  const hours = Math.floor(total / 3600)
  const minutes = Math.floor((total % 3600) / 60)

  if (hours > 0) return `+${hours}h ${minutes}m`
  if (minutes > 0) return `+${minutes}m`
  return `+${total}s`
}

export class BloomMode {
  constructor(journeyController, route, globeController) {
    this._journey = journeyController
    this._route = route
    this._globeController = globeController
    this._globe = globeController.globe
    this._segments = [...(route.segments || [])].sort((left, right) => left.segmentIndex - right.segmentIndex)
    this._hops = route.hops || []
    this._activePerspective = this._journey.activePerspective

    this._playing = false
    this._dragging = false
    this._completed = false
    this._speed = 1
    this._progress = 0
    this._startedAt = 0
    this._rafId = null
    this._timeouts = []
    this._tags = []
    this._rings = []
    this._visibleCount = 0
    this._thresholds = this._buildThresholds()
    this._origin = this._hops[0]
  }

  start() {
    if (!this._globe || !this._origin) return

    this._mountHud()
    this._renderAt(0, { immediate: true, fromScrub: true })

    this._globe.pointOfView({
      lat: this._origin.lat,
      lng: this._origin.lng,
      altitude: 3.5
    }, 1500)

    const controls = this._globe.controls()
    controls.autoRotate = true
    controls.autoRotateSpeed = 0.08

    this._playing = true
    this._startedAt = performance.now()
    this._rafId = requestAnimationFrame((timestamp) => this._tick(timestamp))
  }

  destroy() {
    this._playing = false
    this._dragging = false
    this._completed = false

    if (this._rafId) cancelAnimationFrame(this._rafId)
    this._rafId = null

    this._timeouts.forEach((timeoutId) => clearTimeout(timeoutId))
    this._timeouts = []

    this._clearTags()
    this._clearRings()

    if (this._globe) this._globe.controls().autoRotate = false
  }

  syncHud() {
    if (!this._hud) return

    this._hud.querySelectorAll("[data-speed]").forEach((button) => {
      button.classList.toggle("is-active", Number(button.dataset.speed) === this._speed)
    })

    const muteButton = this._hud.querySelector("[data-bloom-mute]")
    if (muteButton) muteButton.textContent = this._journey.muted ? "MUTE" : "AUDIO"
  }

  setSpeed(speed) {
    const nextSpeed = clamp(Number(speed) || 1, 1, 5)
    if (nextSpeed === this._speed) return

    const elapsed = performance.now() - this._startedAt
    const progress = clamp(elapsed / this._playbackDuration(), 0, 1)
    this._speed = nextSpeed
    this._startedAt = performance.now() - (progress * this._playbackDuration())
    this.syncHud()
  }

  beginScrub() {
    this._dragging = true
    this._playing = false
  }

  seekToProgress(progress) {
    const nextProgress = clamp(progress, 0, 1)
    this._progress = nextProgress
    this._renderAt(nextProgress, { immediate: true, fromScrub: true })
  }

  endScrub(progress) {
    const nextProgress = clamp(progress, 0, 1)
    this._progress = nextProgress
    this._renderAt(nextProgress, { immediate: true, fromScrub: true })
    this._dragging = false
    this._playing = true
    this._completed = false
    this._startedAt = performance.now() - (nextProgress * this._playbackDuration())
    if (!this._rafId) this._rafId = requestAnimationFrame((timestamp) => this._tick(timestamp))
  }

  _tick(timestamp) {
    if (!this._playing) {
      this._rafId = null
      return
    }

    const progress = clamp((timestamp - this._startedAt) / this._playbackDuration(), 0, 1)
    this._progress = progress
    this._renderAt(progress, { immediate: false, fromScrub: false })

    if (progress >= 1) {
      this._complete()
      return
    }

    this._rafId = requestAnimationFrame((nextTimestamp) => this._tick(nextTimestamp))
  }

  _renderAt(progress, { immediate, fromScrub }) {
    const nextVisibleCount = this._thresholds.filter((threshold) => progress >= threshold).length
    const visibleSegments = this._segments.slice(0, nextVisibleCount)
    const visibleHops = this._hops.slice(0, nextVisibleCount + 1)

    if (nextVisibleCount < this._visibleCount) {
      this._clearTags()
      this._clearRings()
    }

    if (nextVisibleCount > this._visibleCount) {
      for (let index = this._visibleCount; index < nextVisibleCount; index += 1) {
        this._revealSegment(this._segments[index], index, { immediate, fromScrub })
      }
    }

    const points = visibleHops.map((hop, index) => ({
      lat: hop.lat,
      lng: hop.lng,
      size: index === 0 ? 1.2 : 0.22,
      radius: index === 0 ? 2.1 : 0.45,
      color: index === 0 ? "#ffffff" : this._pointColorForHop(hop),
      _journey: true
    }))

    if (this._globe) {
      this._globe
        .pointsData(points)
        .arcsData(visibleSegments.map((segment) => this._segmentArc(segment, immediate)))
        .ringsData(this._activeRings())
    }

    this._visibleCount = nextVisibleCount
    this._updateCounters(visibleHops, visibleSegments)
    this._updateScrubber(progress)
  }

  _segmentArc(segment, immediate, finalOpacity = 1) {
    const matchesPerspective = this._matchesPerspective(segment.targetPerspectiveSlug)
    const opacity = matchesPerspective ? finalOpacity : Math.min(finalOpacity, 0.4)

    return {
      ...segment,
      color: rgba(segment.journeyColor || segment.color || "#00f0ff", opacity),
      arcDashLength: 0.4,
      arcDashGap: 0.2,
      arcDashAnimateTime: immediate ? 200 : 1500,
      arcStroke: matchesPerspective ? 2.3 : 1.5,
      _journey: true
    }
  }

  _revealSegment(segment, index, { immediate, fromScrub }) {
    const hop = this._hops[index + 1]
    if (!hop) return

    const matchesPerspective = this._matchesPerspective(hop.perspectiveSlug)
    const ring = {
      lat: hop.lat,
      lng: hop.lng,
      color: rgba(segment.journeyColor || segment.color || "#00f0ff", matchesPerspective ? 0.9 : 0.45),
      maxRadius: matchesPerspective ? 9 : 6,
      propagationSpeed: 2.6,
      repeatPeriod: 1800
    }

    this._rings.push(ring)
    this._globe?.ringsData(this._activeRings())

    const removeTimeout = window.setTimeout(() => {
      this._rings = this._rings.filter((activeRing) => activeRing !== ring)
      this._globe?.ringsData(this._activeRings())
    }, 3200)
    this._timeouts.push(removeTimeout)

    if (fromScrub) return

    this._showTag(segment, hop)
    this._journey.playTone(880 + (index * 40), 80, 0.12)
  }

  _showTag(segment, hop) {
    const position = this._globeController.getScreenPosition(hop.lat, hop.lng)
    if (!position || !this._hud) return

    this._tags = this._tags.filter((tag) => {
      const previousX = Number(tag.dataset.x)
      const previousY = Number(tag.dataset.y)
      if (Math.hypot(previousX - position.x, previousY - position.y) < 80) {
        tag.remove()
        return false
      }
      return true
    })

    const tag = document.createElement("div")
    tag.className = "vt-transmission-tag"
    tag.dataset.x = position.x
    tag.dataset.y = position.y
    tag.style.left = `${position.x + 14}px`
    tag.style.top = `${position.y - 28}px`
    tag.innerHTML = `
      <div class="vt-transmission-source">${segment.targetSourceName || "UNKNOWN"} · ${formatDelay(this._elapsedFromOrigin(hop))}</div>
      <div class="vt-transmission-shift" style="color:${segment.journeyColor || segment.color || "#00f0ff"}">↑ ${hop.framingLabel}</div>
    `

    this._hud.appendChild(tag)
    this._tags.push(tag)

    const fadeTimeout = window.setTimeout(() => {
      tag.classList.add("is-fading")
      const removeTimeout = window.setTimeout(() => {
        tag.remove()
        this._tags = this._tags.filter((activeTag) => activeTag !== tag)
      }, 300)
      this._timeouts.push(removeTimeout)
    }, 3000)
    this._timeouts.push(fadeTimeout)
  }

  _updateCounters(visibleHops, visibleSegments) {
    if (!this._hud) return

    const origin = this._origin
    const lastHop = visibleHops[visibleHops.length - 1] || origin

    const spread = visibleHops.reduce((maxDistance, hop) => {
      const distance = this._haversine(origin.lat, origin.lng, hop.lat, hop.lng)
      return Math.max(maxDistance, distance)
    }, 0)

    const drift = Math.abs((lastHop?.manipulationScore || 0) - (origin?.manipulationScore || 0))
    const driftColor = drift >= 70 ? "#ef4444" : drift >= 40 ? "#f59e0b" : "#22c55e"

    this._hud.querySelector("[data-bloom-outlets]").textContent = String(Math.max(1, visibleSegments.length + 1))
    this._hud.querySelector("[data-bloom-spread]").textContent = `${Math.round(spread).toLocaleString()} km`
    this._hud.querySelector("[data-bloom-drift]").textContent = `${Math.round(drift)}%`
    this._hud.querySelector("[data-bloom-drift]").style.color = driftColor
    this._hud.querySelector("[data-bloom-drift-fill]").style.width = `${Math.round(drift)}%`
    this._hud.querySelector("[data-bloom-drift-fill]").style.background = driftColor
  }

  _updateScrubber(progress) {
    if (!this._hud || this._dragging) return

    this._hud.querySelector("[data-bloom-scrubber]").value = String(Math.round(progress * 100))
  }

  _activeRings() {
    const originRing = {
      lat: this._origin.lat,
      lng: this._origin.lng,
      color: "rgba(255,255,255,0.95)",
      maxRadius: 20,
      propagationSpeed: 2,
      repeatPeriod: 2000
    }

    return [originRing, ...this._rings]
  }

  _mountHud() {
    const hud = document.createElement("div")
    hud.className = "vt-journey-hud vt-bloom-hud"
    hud.innerHTML = `
      <div class="vt-journey-topbar">
        <div class="vt-mode-badge">
          <span>◉ BLOOM</span>
          <button class="vt-journey-icon-btn" type="button" data-action="click->journey#exit">EXIT</button>
        </div>
        <div class="vt-bloom-toolbar">
          <div class="vt-speed-pills">
            <button class="vt-speed-pill" type="button" data-speed="1" data-action="click->journey#setBloomSpeed">1×</button>
            <button class="vt-speed-pill" type="button" data-speed="2" data-action="click->journey#setBloomSpeed">2×</button>
            <button class="vt-speed-pill" type="button" data-speed="5" data-action="click->journey#setBloomSpeed">5×</button>
          </div>
          <button class="vt-journey-icon-btn" type="button" data-bloom-mute data-action="click->journey#toggleMute"></button>
        </div>
      </div>

      <div class="vt-bloom-counters">
        <div class="vt-bloom-counter">
          <span>OUTLETS REACHED</span>
          <strong data-bloom-outlets>1</strong>
        </div>
        <div class="vt-bloom-counter">
          <span>GEOGRAPHIC SPREAD</span>
          <strong data-bloom-spread>0 km</strong>
        </div>
        <div class="vt-bloom-counter vt-bloom-counter--drift">
          <span>NARRATIVE DRIFT</span>
          <strong data-bloom-drift>0%</strong>
          <div class="vt-bloom-drift-bar">
            <span data-bloom-drift-fill></span>
          </div>
        </div>
      </div>

      <div class="vt-bloom-timeline">
        <span class="vt-bloom-timeline-label">PROPAGATION TIMELINE</span>
        <input class="vt-bloom-scrubber" type="range" min="0" max="100" value="0"
               data-bloom-scrubber
               data-action="pointerdown->journey#startBloomDrag pointerup->journey#endBloomDrag input->journey#scrubBloom change->journey#endBloomDrag">
      </div>
    `

    this._journey.mountHud(hud)
    this._hud = hud
    this.syncHud()
  }

  _buildThresholds() {
    if (this._segments.length === 0) return []

    const start = this._hops[0]?.publishedAt ? Date.parse(this._hops[0].publishedAt) : null
    const finish = this._hops[this._hops.length - 1]?.publishedAt ? Date.parse(this._hops[this._hops.length - 1].publishedAt) : null
    const duration = start && finish && finish > start ? finish - start : 0

    return this._segments.map((segment, index) => {
      const hopTime = this._hops[index + 1]?.publishedAt ? Date.parse(this._hops[index + 1].publishedAt) : null
      if (duration > 0 && hopTime) return clamp((hopTime - start) / duration, 0.05, 1)
      return clamp((index + 1) / this._segments.length, 0.05, 1)
    })
  }

  _matchesPerspective(slug) {
    return this._activePerspective === "all" || slug === this._activePerspective
  }

  _pointColorForHop(hop) {
    const baseColor = hop.journeyColor || hop.framingColor || "#00f0ff"
    return this._matchesPerspective(hop.perspectiveSlug) ? rgba(baseColor, 0.92) : rgba(baseColor, 0.35)
  }

  _elapsedFromOrigin(hop) {
    const originTime = this._origin?.publishedAt ? Date.parse(this._origin.publishedAt) : null
    const hopTime = hop?.publishedAt ? Date.parse(hop.publishedAt) : null
    if (!originTime || !hopTime) return hop?.delaySeconds || 0
    return Math.max(0, Math.round((hopTime - originTime) / 1000))
  }

  _clearTags() {
    this._tags.forEach((tag) => tag.remove())
    this._tags = []
  }

  _clearRings() {
    this._rings = []
    this._globe?.ringsData(this._activeRings())
  }

  _haversine(lat1, lng1, lat2, lng2) {
    const degreesToRadians = Math.PI / 180
    const earthRadiusKm = 6371
    const deltaLat = (lat2 - lat1) * degreesToRadians
    const deltaLng = (lng2 - lng1) * degreesToRadians
    const startLat = lat1 * degreesToRadians
    const endLat = lat2 * degreesToRadians

    const a = Math.sin(deltaLat / 2) ** 2 +
      Math.cos(startLat) * Math.cos(endLat) * Math.sin(deltaLng / 2) ** 2

    return earthRadiusKm * 2 * Math.asin(Math.sqrt(a))
  }

  _playbackDuration() {
    return BASE_PLAYBACK_MS / this._speed
  }

  _complete() {
    if (this._completed) return

    this._completed = true
    this._playing = false

    if (this._rafId) cancelAnimationFrame(this._rafId)
    this._rafId = null

    if (this._globe) {
      this._globe.controls().autoRotate = false
      this._globe.arcsData(this._segments.map((segment) => this._segmentArc(segment, true, 0.8)))
    }

    const timeoutId = window.setTimeout(() => {
      this._journey.showSummary()
    }, 1500)
    this._timeouts.push(timeoutId)
  }
}
