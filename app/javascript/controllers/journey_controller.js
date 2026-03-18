import { Controller } from "@hotwired/stimulus"
import { BloomMode } from "controllers/bloom_controller"
import { ChronicleMode } from "controllers/chronicle_controller"

const MUTE_STORAGE_KEY = "veritas:journeyMuted"

export default class extends Controller {
  static targets = ["globeSection", "hudLayer", "summarySlot", "feedList"]

  connect() {
    this._active = false
    this._mode = null
    this._route = null
    this._routeId = null
    this._segments = []
    this._preJourneyState = null
    this._modeInstance = null
    this._audioContext = null
    this._muted = localStorage.getItem(MUTE_STORAGE_KEY) === "true"

    this._startHandler = (event) => this._startFromEvent(event)
    this._exitHandler = () => this.exit()
    this._keyHandler = (event) => this._handleKeydown(event)
    this._documentClickHandler = (event) => this._handleDocumentClick(event)

    window.addEventListener("veritas:startJourney", this._startHandler)
    window.addEventListener("veritas:exitJourney", this._exitHandler)
    window.addEventListener("keydown", this._keyHandler)
    document.addEventListener("click", this._documentClickHandler)
  }

  disconnect() {
    window.removeEventListener("veritas:startJourney", this._startHandler)
    window.removeEventListener("veritas:exitJourney", this._exitHandler)
    window.removeEventListener("keydown", this._keyHandler)
    document.removeEventListener("click", this._documentClickHandler)
    this._teardown({ restore: false, preserveState: false })
  }

  get activePerspective() {
    return localStorage.getItem("veritas:perspective") || "all"
  }

  get globeController() {
    return document.getElementById("globe-container")?.__controller || null
  }

  get globe() {
    return this.globeController?.globe || null
  }

  get route() {
    return this._route
  }

  get muted() {
    return this._muted
  }

  exit() {
    if (!this._active) return

    this._teardown({ restore: true, preserveState: false })
  }

  toggleMute() {
    this._muted = !this._muted
    localStorage.setItem(MUTE_STORAGE_KEY, String(this._muted))
    this._modeInstance?.syncHud?.()
  }

  setBloomSpeed(event) {
    this._modeInstance?.setSpeed?.(parseFloat(event.currentTarget.dataset.speed || "1"))
  }

  scrubBloom(event) {
    this._modeInstance?.seekToProgress?.(Number(event.currentTarget.value) / 100)
  }

  startBloomDrag() {
    this._modeInstance?.beginScrub?.()
  }

  endBloomDrag(event) {
    this._modeInstance?.endScrub?.(Number(event.currentTarget.value) / 100)
  }

  chroniclePrev() {
    this._modeInstance?.retreat?.()
  }

  chronicleNext() {
    this._modeInstance?.advance?.()
  }

  chronicleAuto() {
    this._modeInstance?.toggleAuto?.()
  }

  chroniclePause() {
    this._modeInstance?.togglePause?.()
  }

  chronicleJump(event) {
    this._modeInstance?.jumpTo?.(Number(event.currentTarget.dataset.hopIndex))
  }

  armChronicleAutoCycle() {
    this._modeInstance?.armAutoCycle?.()
  }

  releaseChronicleAutoCycle() {
    this._modeInstance?.releaseAutoCycle?.()
  }

  replayBloom() {
    this._restart("bloom")
  }

  replayChronicle() {
    this._restart("chronicle")
  }

  mountHud(element) {
    this.hudLayerTarget.innerHTML = ""
    if (element) this.hudLayerTarget.appendChild(element)
  }

  clearHud() {
    this.hudLayerTarget.innerHTML = ""
  }

  showSummary() {
    if (!this._route) return

    const summary = this._buildSummary()
    const host = this._summaryHost()
    host.innerHTML = this._summaryTemplate(summary)
    host.classList.add("is-visible")
    this.playChord([440, 554, 659], 200, 0.08)
  }

  clearSummary() {
    this.summarySlotTarget.innerHTML = ""
    this.summarySlotTarget.classList.remove("is-visible")
    const mobileHost = this.hudLayerTarget.querySelector(".vt-journey-summary-slot")
    if (mobileHost) mobileHost.remove()
  }

  highlightSidebarArticle(articleId) {
    const cards = this._feedCards()

    cards.forEach((card) => {
      card.classList.remove("is-active", "is-journey-current")
    })

    if (!articleId) return

    const current = cards.find((card) => String(card.dataset.articleId) === String(articleId))
    if (!current) return

    current.classList.add("is-active", "is-journey-current")
    current.scrollIntoView({ behavior: "smooth", block: "nearest" })
  }

  prepareSidebar() {
    const articleIds = new Set((this._route?.hops || []).map((hop) => hop.articleId).filter(Boolean).map(String))

    this._feedCards().forEach((card) => {
      const inJourney = articleIds.has(String(card.dataset.articleId))
      card.classList.toggle("is-journey-member", inJourney)
      card.classList.toggle("is-journey-dimmed", articleIds.size > 0 && !inJourney)
    })
  }

  resetSidebar() {
    this._feedCards().forEach((card) => {
      card.classList.remove("is-active", "is-journey-current", "is-journey-member", "is-journey-dimmed")
    })
  }

  playTone(frequencies, durationMs, volume = 0.12, type = "sine") {
    if (this._muted) return

    try {
      if (!this._audioContext) {
        const AudioContextClass = window.AudioContext || window.webkitAudioContext
        if (!AudioContextClass) return
        this._audioContext = new AudioContextClass()
      }

      const context = this._audioContext
      const tones = Array.isArray(frequencies) ? frequencies : [frequencies]

      tones.forEach((frequency) => {
        const oscillator = context.createOscillator()
        const gain = context.createGain()

        oscillator.type = type
        oscillator.frequency.setValueAtTime(frequency, context.currentTime)
        gain.gain.setValueAtTime(volume, context.currentTime)
        gain.gain.exponentialRampToValueAtTime(0.001, context.currentTime + (durationMs / 1000))

        oscillator.connect(gain)
        gain.connect(context.destination)
        oscillator.start(context.currentTime)
        oscillator.stop(context.currentTime + (durationMs / 1000))
      })
    } catch (_error) {
      // Web Audio is optional for the demo.
    }
  }

  playChord(frequencies, durationMs, volume) {
    this.playTone(frequencies, durationMs, volume, "sine")
  }

  formatTime(value) {
    if (!value) return "Unknown"

    return new Date(value).toLocaleTimeString([], {
      hour: "2-digit",
      minute: "2-digit",
      timeZone: "UTC",
      timeZoneName: "short"
    }).replace("GMT", "UTC")
  }

  formatDuration(totalSeconds) {
    const seconds = Math.max(0, Math.round(totalSeconds || 0))
    const hours = Math.floor(seconds / 3600)
    const minutes = Math.floor((seconds % 3600) / 60)

    if (hours > 0) return `${hours}h ${minutes}m`
    if (minutes > 0) return `${minutes}m`
    return `${seconds}s`
  }

  framingLevel(score) {
    if (score <= 20) return "ORIGINAL"
    if (score <= 40) return "AMPLIFIED"
    if (score <= 60) return "CONCERNING"
    if (score <= 80) return "HOSTILE"
    return "CRITICAL THREAT"
  }

  _startFromEvent(event) {
    const { mode, route, routeId, segments } = event.detail || {}
    const resolvedRoute = route || this._buildRouteFromSegments(routeId, segments)

    if (!resolvedRoute || !resolvedRoute.segments?.length) return

    this._startJourney(mode || "bloom", resolvedRoute, routeId || resolvedRoute.routeId || resolvedRoute.id)
  }

  _startJourney(mode, route, routeId) {
    const globeController = this.globeController
    if (!globeController) return

    const preserveState = this._preJourneyState
    if (this._active) this._teardown({ restore: false, preserveState: true })

    this._mode = mode
    this._route = route
    this._routeId = routeId
    this._segments = [...(route.segments || [])].sort((left, right) => left.segmentIndex - right.segmentIndex)
    this._preJourneyState = preserveState || globeController.captureJourneyState?.()
    this._active = true

    this.element.classList.add("vt-journey-active", `vt-journey-${mode}`)
    this.globeSectionTarget.classList.add("is-journey-active", `is-${mode}`)

    this.clearSummary()
    this.prepareSidebar()

    window.dispatchEvent(new CustomEvent(`veritas:${mode}Active`, {
      detail: {
        mode,
        routeId: this._routeId,
        state: this._preJourneyState
      }
    }))

    this._modeInstance = mode === "chronicle"
      ? new ChronicleMode(this, route, globeController)
      : new BloomMode(this, route, globeController)

    this._modeInstance.start()
  }

  _restart(mode) {
    if (!this._route) return

    this._startJourney(mode, this._route, this._routeId)
  }

  _teardown({ restore, preserveState }) {
    this._modeInstance?.destroy?.()
    this._modeInstance = null
    this._active = false

    this.clearHud()
    this.clearSummary()
    this.resetSidebar()

    this.element.classList.remove("vt-journey-active", "vt-journey-bloom", "vt-journey-chronicle")
    this.globeSectionTarget.classList.remove("is-journey-active", "is-bloom", "is-chronicle")

    if (restore) {
      window.dispatchEvent(new CustomEvent("veritas:journeyEnded", {
        detail: {
          routeId: this._routeId,
          state: this._preJourneyState
        }
      }))
    }

    this._mode = null
    this._route = null
    this._routeId = null
    this._segments = []
    if (!preserveState) this._preJourneyState = null
  }

  _buildRouteFromSegments(routeId, segments = []) {
    if (!segments.length) return null

    const sortedSegments = [...segments].sort((left, right) => left.segmentIndex - right.segmentIndex)
    const originSegment = sortedSegments[0]
    const hops = [
      {
        index: 0,
        articleId: originSegment.sourceArticleId,
        sourceName: originSegment.sourceName,
        headline: originSegment.sourceHeadline,
        country: originSegment.sourceCountry,
        city: originSegment.sourceCity,
        lat: originSegment.startLat,
        lng: originSegment.startLng,
        publishedAt: originSegment.sourcePublishedAt,
        delaySeconds: 0,
        framingShift: "original",
        framingLabel: originSegment.sourceFramingLabel || "ORIGINAL",
        framingColor: originSegment.color,
        journeyColor: originSegment.journeyColor,
        manipulationScore: 10,
        confidenceScore: originSegment.confidenceScore,
        semanticSimilarity: originSegment.semanticSimilarity,
        sentimentLabel: originSegment.sourceSentimentLabel,
        trustScore: originSegment.sourceTrustScore,
        perspectiveSlug: originSegment.sourcePerspectiveSlug,
        perspectiveLabel: originSegment.sourcePerspectiveLabel,
        perspectiveColor: originSegment.sourcePerspectiveColor
      }
    ]

    sortedSegments.forEach((segment, index) => {
      hops.push({
        index: index + 1,
        articleId: segment.targetArticleId,
        sourceName: segment.targetSourceName,
        headline: segment.targetHeadline,
        country: segment.targetCountry,
        city: segment.targetCity,
        lat: segment.endLat,
        lng: segment.endLng,
        publishedAt: segment.targetPublishedAt,
        delaySeconds: segment.delaySeconds,
        framingShift: segment.framingShift,
        framingLabel: segment.targetFramingLabel || this.framingLevel(segment.manipulationScore || 10),
        framingColor: segment.color,
        journeyColor: segment.journeyColor,
        manipulationScore: segment.manipulationScore,
        confidenceScore: segment.confidenceScore,
        semanticSimilarity: segment.semanticSimilarity,
        sentimentLabel: segment.targetSentimentLabel,
        trustScore: segment.targetTrustScore,
        perspectiveSlug: segment.targetPerspectiveSlug,
        perspectiveLabel: segment.targetPerspectiveLabel,
        perspectiveColor: segment.targetPerspectiveColor
      })
    })

    return {
      id: routeId,
      routeId,
      routeName: sortedSegments[0].routeName,
      totalHops: hops.length,
      totalSegments: sortedSegments.length,
      totalDurationSeconds: this._durationBetween(hops[0], hops[hops.length - 1]),
      originCountry: hops[0].country,
      targetCountry: hops[hops.length - 1].country,
      hops,
      segments: sortedSegments
    }
  }

  _buildSummary() {
    const hops = this._route?.hops || []
    const segments = this._route?.segments || []
    const origin = hops[0]
    const finalHop = hops[hops.length - 1]
    const drift = finalHop?.manipulationScore || 0
    const uniqueCountries = new Set(hops.map((hop) => hop.country).filter(Boolean))
    const peakSegment = segments.reduce((peak, segment) => {
      if (!peak) return segment

      const peakDrop = (peak.sourceTrustScore ?? 0) - (peak.targetTrustScore ?? 0)
      const currentDrop = (segment.sourceTrustScore ?? 0) - (segment.targetTrustScore ?? 0)
      return currentDrop > peakDrop ? segment : peak
    }, null)

    const framingJourney = []
    hops.forEach((hop, index) => {
      const previous = framingJourney[framingJourney.length - 1]
      if (previous && previous.label === hop.framingLabel) {
        previous.end = index + 1
        previous.sources.push(`${hop.sourceName}, ${hop.city || hop.country}`)
        return
      }

      framingJourney.push({
        label: hop.framingLabel,
        color: hop.journeyColor || hop.framingColor || "#22c55e",
        start: index + 1,
        end: index + 1,
        sources: [`${hop.sourceName}, ${hop.city || hop.country}`]
      })
    })

    return {
      origin,
      finalHop,
      duration: this._route?.totalDurationSeconds || this._durationBetween(origin, finalHop),
      outletCount: hops.length,
      countryCount: uniqueCountries.size,
      drift,
      driftLabel: drift >= 80 ? "CRITICAL" : drift >= 60 ? "HIGH" : drift >= 40 ? "ELEVATED" : "LOW",
      framingJourney,
      peakSegment
    }
  }

  _summaryTemplate(summary) {
    const driftGradient = summary.drift >= 80 ? "linear-gradient(90deg, #22c55e, #f59e0b, #ef4444)"
      : summary.drift >= 40 ? "linear-gradient(90deg, #22c55e, #f59e0b)"
      : "linear-gradient(90deg, #22c55e, #38bdf8)"

    const journeyItems = summary.framingJourney.map((group) => {
      const hopRange = group.start === group.end ? `hop ${group.start}` : `hops ${group.start}-${group.end}`
      return `
        <div class="vt-summary-journey-row">
          <span class="vt-summary-journey-dot" style="background:${group.color};"></span>
          <div>
            <div class="vt-summary-journey-label">${group.label}</div>
            <div class="vt-summary-journey-meta">${hopRange} · ${group.sources.join(" · ")}</div>
          </div>
        </div>
      `
    }).join("")

    const trustDrop = summary.peakSegment
      ? Math.max(0, Math.round((summary.peakSegment.sourceTrustScore ?? 0) - (summary.peakSegment.targetTrustScore ?? 0)))
      : 0

    return `
      <div class="vt-journey-summary-card">
        <div class="vt-summary-header">
          <div>
            <div class="vt-summary-kicker">PROPAGATION COMPLETE</div>
            <div class="vt-summary-title">${this._route?.routeName || "Narrative Journey"}</div>
          </div>
          <button class="vt-journey-icon-btn" type="button" data-action="click->journey#exit">✕</button>
        </div>

        <div class="vt-summary-grid">
          <div><span>Origin</span><strong>${summary.origin?.sourceName || "Unknown"} · ${summary.origin?.city || summary.origin?.country || "Unknown"} · ${this.formatTime(summary.origin?.publishedAt)}</strong></div>
          <div><span>Final</span><strong>${summary.finalHop?.sourceName || "Unknown"} · ${summary.finalHop?.city || summary.finalHop?.country || "Unknown"} · ${this.formatTime(summary.finalHop?.publishedAt)}</strong></div>
          <div><span>Duration</span><strong>${this.formatDuration(summary.duration)}</strong></div>
          <div><span>Outlets</span><strong>${summary.outletCount} across ${summary.countryCount} countries</strong></div>
        </div>

        <div class="vt-summary-drift">
          <div class="vt-summary-section-title">NARRATIVE DRIFT</div>
          <div class="vt-summary-drift-bar">
            <span class="vt-summary-drift-fill" style="width:${summary.drift}%;background:${driftGradient};"></span>
          </div>
          <div class="vt-summary-drift-meta">${summary.drift}% · ${summary.driftLabel}</div>
        </div>

        <div class="vt-summary-section">
          <div class="vt-summary-section-title">FRAMING JOURNEY</div>
          ${journeyItems}
        </div>

        <div class="vt-summary-peak">
          <span>PEAK DISTORTION</span>
          <strong>${summary.peakSegment ? `Hop ${summary.peakSegment.segmentIndex + 1} (${summary.peakSegment.sourceName} -> ${summary.peakSegment.targetSourceName}) · ↓${trustDrop} pts trust` : "No measurable trust drop"}</strong>
        </div>

        <div class="vt-summary-actions">
          <button class="vt-summary-action vt-summary-action--bloom" type="button" data-action="click->journey#replayBloom">◉ REPLAY BLOOM</button>
          <button class="vt-summary-action vt-summary-action--chronicle" type="button" data-action="click->journey#replayChronicle">▶ REPLAY CHRONICLE</button>
          <button class="vt-summary-action" type="button" data-action="click->journey#exit">✕ EXIT</button>
        </div>
      </div>
    `
  }

  _durationBetween(origin, finalHop) {
    const start = origin?.publishedAt ? Date.parse(origin.publishedAt) : null
    const finish = finalHop?.publishedAt ? Date.parse(finalHop.publishedAt) : null
    if (!start || !finish) return 0

    return Math.max(0, Math.round((finish - start) / 1000))
  }

  _feedCards() {
    return Array.from(this.feedListTarget?.querySelectorAll(".veritas-feed-card") || [])
  }

  _summaryHost() {
    const sidebarVisible = this.summarySlotTarget.offsetParent !== null
    if (sidebarVisible) return this.summarySlotTarget

    let mobileHost = this.hudLayerTarget.querySelector(".vt-journey-summary-slot")
    if (!mobileHost) {
      mobileHost = document.createElement("div")
      mobileHost.className = "vt-journey-summary-slot"
      this.hudLayerTarget.appendChild(mobileHost)
    }

    return mobileHost
  }

  _handleKeydown(event) {
    if (!this._active) return
    if (event.key === "Escape") this.exit()
  }

  _handleDocumentClick(event) {
    if (!this._active) return

    if (this.hudLayerTarget.contains(event.target)) return
    if (this.summarySlotTarget.contains(event.target)) return
    if (event.target.closest(".vt-route-choice-menu")) return
    if (event.target.closest(".veritas-feed-card")) return

    if (event.target.closest("#globe-container")) this.exit()
  }
}
