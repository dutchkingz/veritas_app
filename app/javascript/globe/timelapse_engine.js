// Timelapse Engine — cinematic playback of narrative arcs.
// Receives the globe controller instance for access to shared state.

import { getFramingColor, interpolateColor, dominantConnectionType } from "globe/color_utils"

export class TimelapseEngine {
  constructor(controller) {
    this._c = controller
    this._state = null
    this._overlay = null
    this._preState = null
    this._context = { mode: 'exploration', routeId: null }
  }

  get active() { return !!this._state }
  get state() { return this._state }

  get _globe() { return this._c._globe }

  toggle() {
    if (this._state) {
      this.exit()
    } else {
      this._context = { mode: 'exploration', routeId: null }
      setTimeout(() => this._start(), 150)
    }
  }

  startStory(routeId) {
    if (this._state) this._exitImmediate()
    this._context = { mode: 'story', routeId: routeId }
    setTimeout(() => this._start(), 150)
  }

  // ---- DATA PREPARATION ----

  _prepareExplorationData() {
    const allArcs = this._c._allArcs || []
    if (allArcs.length === 0) return []

    const routeMap = new Map()
    allArcs.forEach(seg => {
      const routeId = seg.routeId
      if (!routeId) return
      if (!routeMap.has(routeId)) {
        routeMap.set(routeId, { segments: [], maxDrift: 0 })
      }
      const route = routeMap.get(routeId)
      route.segments.push(seg)
      route.maxDrift = Math.max(route.maxDrift, seg.driftIntensity || 0)
    })

    const topRoutes = [...routeMap.entries()]
      .sort((a, b) => b[1].maxDrift - a[1].maxDrift)
      .slice(0, 3)

    if (topRoutes.length === 0) return []

    const timelapseSegments = []
    topRoutes.forEach(([routeId, data]) => {
      data.segments.forEach(seg => {
        timelapseSegments.push({
          ...seg,
          _routeIndex: topRoutes.findIndex(r => r[0] === routeId),
          _timestamp: new Date(seg.sourcePublishedAt || seg.publishedAt || 0).getTime()
        })
      })
    })

    return this._normalizeTimestamps(timelapseSegments)
  }

  _prepareStoryData(routeId) {
    const allArcs = this._c._allArcs || []

    const routeSegments = allArcs.filter(seg =>
      String(seg.routeId) === String(routeId)
    )

    if (routeSegments.length === 0) {
      const route = (this._c._allRoutes || []).find(r =>
        String(r.routeId || r.id) === String(routeId)
      )
      if (route && route.segments && route.segments.length > 0) {
        console.log(`[Timelapse/Story] Route ${routeId}: using route.segments (${route.segments.length} hops)`)
        const segments = route.segments.map(seg => ({
          ...seg,
          _routeIndex: 0,
          _timestamp: new Date(seg.sourcePublishedAt || seg.publishedAt || 0).getTime()
        }))
        return this._normalizeTimestamps(segments)
      }
      console.warn(`[Timelapse/Story] Route ${routeId}: no segments found — aborting`)
      return []
    }

    const storySegments = routeSegments.map(seg => ({
      ...seg,
      _routeIndex: 0,
      _timestamp: new Date(seg.sourcePublishedAt || seg.publishedAt || 0).getTime()
    }))

    console.log(`[Timelapse/Story] Route ${routeId}: ${storySegments.length} hops found`)
    return this._normalizeTimestamps(storySegments)
  }

  _normalizeTimestamps(segments) {
    segments.sort((a, b) => a._timestamp - b._timestamp)

    if (segments.length > 0) {
      const t0 = segments[0]._timestamp
      const tN = segments[segments.length - 1]._timestamp
      const range = tN - t0 || 1
      segments.forEach(seg => {
        seg._normalizedTime = (seg._timestamp - t0) / range
      })
    }

    return segments
  }

  // ---- PLAYBACK ----

  _start() {
    if (!this._globe) return
    if (this._c._journeyActive) return

    const ctx = this._context
    const segments = ctx.mode === 'story' && ctx.routeId
      ? this._prepareStoryData(ctx.routeId)
      : this._prepareExplorationData()

    if (segments.length === 0) return

    const duration = ctx.mode === 'story' ? 15000 : 12000

    console.log(`[Timelapse] Starting ${ctx.mode} mode — ${segments.length} segments, ${duration / 1000}s${ctx.routeId ? `, route: ${ctx.routeId}` : ''}`)

    this._state = {
      segments: segments,
      activeArcs: [],
      currentTime: 0,
      startedAt: null,
      playing: true,
      revealedCount: 0,
      _pausedAt: null,
      _latestArcId: null,
      _duration: duration,
      _mode: ctx.mode,
      _routeId: ctx.routeId
    }

    this._preState = {
      arcsData: this._c._cloneLayer(this._globe.arcsData() || []),
      hexBinPointsData: this._c._cloneLayer(this._globe.hexBinPointsData() || []),
      ringsData: this._c._cloneLayer(this._globe.ringsData() || []),
      pointOfView: { ...(this._globe.pointOfView?.() || { lat: 20, lng: 10, altitude: 2.5 }) },
      autoRotate: this._globe.controls().autoRotate,
      autoRotateSpeed: this._globe.controls().autoRotateSpeed,
      packetVisible: this._c._packetAnimator?.group ? this._c._packetAnimator?.group.visible !== false : true
    }

    this._globe.arcsData([]).ringsData([])
    if (this._c._packetAnimator?.group) this._c._packetAnimator.group.visible = false
    this._globe.controls().autoRotate = false

    this._applyTimelapseCallbacks()
    this._enterTimelapseMode()

    window.dispatchEvent(new CustomEvent("veritas:timelapseState", {
      detail: { active: true }
    }))

    this._state.startedAt = performance.now() + 300
    setTimeout(() => this._frame(), 300)
  }

  _frame() {
    const state = this._state
    if (!state || !state.playing) return

    const duration = state._duration || 12000
    const elapsed = performance.now() - state.startedAt
    state.currentTime = Math.min(elapsed / duration, 1.0)

    const newlyRevealed = []
    while (
      state.revealedCount < state.segments.length &&
      state.segments[state.revealedCount]._normalizedTime <= state.currentTime
    ) {
      const seg = state.segments[state.revealedCount]
      seg._revealTime = performance.now()
      seg._opacity = 0
      state.activeArcs.push(seg)
      newlyRevealed.push(seg)
      state.revealedCount++
    }

    newlyRevealed.forEach(seg => this._onArcReveal(seg))

    if (newlyRevealed.length > 0) {
      const latest = newlyRevealed[newlyRevealed.length - 1]
      state._latestArcId = latest.id || latest._timestamp
    }

    const now = performance.now()
    state.activeArcs.forEach(arc => {
      arc._opacity = Math.min((now - arc._revealTime) / 300, 1.0)
      arc._isLatest = (arc.id || arc._timestamp) === state._latestArcId
    })

    if (newlyRevealed.length > 0) {
      this._globe.arcsData([...state.activeArcs])
    }

    if (newlyRevealed.length > 0) {
      this._smoothCamera(newlyRevealed[newlyRevealed.length - 1])
    }

    if (newlyRevealed.length > 0) {
      this._updateOverlay(newlyRevealed[newlyRevealed.length - 1], state)
    }

    this._updateProgress(state)

    if (state.currentTime >= 1.0) {
      setTimeout(() => this._end(), 1500)
    } else {
      requestAnimationFrame(() => this._frame())
    }
  }

  _applyTimelapseCallbacks() {
    if (!this._globe) return

    this._globe
      .arcColor(d => {
        const opacity = d._opacity != null ? d._opacity : 1
        const threat = d.veritasThreatScore || 0
        const vis = d.visibilityWeight || 0.3
        const boost = d._isLatest ? 1.3 : 1.0

        let targetRGB
        if (d.gdeltQuadClass === 4 || threat >= 7) {
          targetRGB = { r: 255, g: 40, b: 40 }
        } else if (d.gdeltQuadClass === 3 || threat >= 5) {
          targetRGB = { r: 255, g: 140, b: 0 }
        } else if (threat >= 3) {
          targetRGB = { r: 255, g: 215, b: 0 }
        } else {
          targetRGB = { r: 96, g: 136, b: 160 }
        }

        const visAlpha = vis * 0.85 * opacity

        const sourceColor = {
          r: Math.min(255, Math.round(74 * boost)),
          g: Math.min(255, Math.round(96 * boost)),
          b: Math.min(255, Math.round(112 * boost)),
          a: visAlpha
        }
        const targetColor = {
          r: Math.min(255, Math.round(targetRGB.r * boost)),
          g: Math.min(255, Math.round(targetRGB.g * boost)),
          b: Math.min(255, Math.round(targetRGB.b * boost)),
          a: Math.max(0.3, visAlpha)
        }

        if (threat < 2 && vis < 0.5) {
          return `rgba(${sourceColor.r}, ${sourceColor.g}, ${sourceColor.b}, ${sourceColor.a})`
        }

        const stops = 8
        const colors = []
        for (let i = 0; i < stops; i++) {
          const t = i / (stops - 1)
          const eased = t * t
          colors.push(interpolateColor(sourceColor, targetColor, eased))
        }
        return colors
      })
      .arcStroke(d => {
        const baseThickness = 0.6 + (d.driftIntensity || 0) * 1.2
        const revealScale = d._opacity != null ? d._opacity : 1
        const latestBoost = d._isLatest ? 1.4 : 1.0
        return baseThickness * (0.5 + revealScale * 0.5) * latestBoost
      })
      .arcDashAnimateTime(d => {
        const age = performance.now() - (d._revealTime || 0)
        const intensity = d.driftIntensity || 0
        if (age < 1500) return 600
        return 4000 - (intensity * 2800)
      })
      .arcDashLength(d => {
        const f = d.framingShift || 'original'
        if (f === 'original') return 1
        if (f === 'neutralized') return 0.6
        if (f === 'amplified') return 0.4
        if (f === 'distorted') return 0.25
        return 1
      })
      .arcDashGap(d => {
        const f = d.framingShift || 'original'
        if (f === 'original') return 0
        if (f === 'neutralized') return 0.15
        if (f === 'amplified') return 0.2
        if (f === 'distorted') return 0.25
        return 0
      })
  }

  arcStrokeDefault(d) {
    if (this._c._selectedArcArticleId && String(d.articleId) === String(this._c._selectedArcArticleId)) {
      return 2.5
    }
    if (d.connectionTypes) {
      const dom = dominantConnectionType(d)
      const base = d.thickness || 0.5
      if (dom === 'narrative_route') return Math.max(base, 1.0)
      if (dom === 'gdelt_event') return Math.max(base, 0.7)
      if (dom === 'embedding_similarity') return Math.min(base, 0.5)
      if (dom === 'shared_entities') return Math.min(base, 0.3)
      return base
    }
    if (d.arcStroke != null) return d.arcStroke
    if (d.driftIntensity != null) {
      const base = d.tier === 1 ? 1.2 : (d.tier === 2 ? 0.5 : 0.4)
      return base + (d.driftIntensity * 0.8)
    }
    if (d.tier === 1) return 1.2
    if (d.tier === 2) return 0.5
    return d.thickness ? Math.min(d.thickness, 1.0) : 0.4
  }

  _onArcReveal(arc) {
    if (!this._globe) return

    const currentRings = this._globe.ringsData() || []
    const framingColor = getFramingColor(arc.framingShift)
    const ring = {
      lat: arc.startLat,
      lng: arc.startLng,
      maxRadius: 4,
      propagationSpeed: 3,
      repeatPeriod: 0,
      color: () => `${framingColor}cc`,
      threat: 1
    }
    this._globe.ringsData([...currentRings, ring])

    setTimeout(() => {
      if (!this._globe) return
      this._globe.ringsData((this._globe.ringsData() || []).filter(r => r !== ring))
    }, 2000)

    if ((arc.driftIntensity || 0) > 0.5) {
      setTimeout(() => {
        if (!this._globe) return
        const targetRing = {
          lat: arc.endLat,
          lng: arc.endLng,
          maxRadius: 3,
          propagationSpeed: 2,
          repeatPeriod: 0,
          color: () => `${framingColor}88`,
          threat: 1
        }
        const rings = this._globe.ringsData() || []
        this._globe.ringsData([...rings, targetRing])
        setTimeout(() => {
          if (!this._globe) return
          this._globe.ringsData((this._globe.ringsData() || []).filter(r => r !== targetRing))
        }, 2000)
      }, 400)
    }
  }

  _smoothCamera(segment) {
    if (!this._globe) return

    const midLat = (segment.startLat + segment.endLat) / 2
    const midLng = (segment.startLng + segment.endLng) / 2

    const current = this._globe.pointOfView()
    const maxDeg = 60

    const latDiff = midLat - current.lat
    const lngDiff = midLng - current.lng

    const targetLat = current.lat + Math.max(-maxDeg, Math.min(maxDeg, latDiff * 0.4))
    const targetLng = current.lng + Math.max(-maxDeg, Math.min(maxDeg, lngDiff * 0.4))

    this._globe.pointOfView(
      { lat: targetLat, lng: targetLng, altitude: 1.6 },
      1500
    )
  }

  // ---- OVERLAY HUD ----

  _enterTimelapseMode() {
    if (this._overlay) return

    const overlay = document.createElement('div')
    overlay.id = 'timelapse-overlay'
    overlay.style.cssText = 'position:absolute;top:0;left:0;right:0;bottom:0;pointer-events:none;z-index:200;font-family:"JetBrains Mono","Fira Code","SF Mono",monospace;'
    overlay.innerHTML = `
      <div style="
        position: absolute;
        top: 0; left: 0; right: 0; bottom: 0;
        pointer-events: none;
      ">
        <!-- Top center: mode indicator -->
        <div id="tl-header" style="
          position: absolute;
          top: 80px;
          left: 50%;
          transform: translateX(-50%);
          text-align: center;
          opacity: 0;
          transition: opacity 0.8s ease;
        ">
          <div style="
            font-size: 9px;
            letter-spacing: 4px;
            text-transform: uppercase;
            color: rgba(0, 255, 204, 0.5);
            margin-bottom: 4px;
          ">&#9654; NARRATIVE TIMELAPSE &#9664;</div>
          <div id="tl-route-name" style="
            font-size: 14px;
            color: #e0e0e0;
            max-width: 500px;
          "></div>
        </div>

        <!-- Bottom left: current event card -->
        <div id="tl-event-card" style="
          position: absolute;
          bottom: 100px;
          left: 30px;
          background: rgba(10, 12, 18, 0.88);
          backdrop-filter: blur(12px);
          border: 1px solid rgba(0, 255, 204, 0.12);
          border-radius: 6px;
          padding: 16px 20px;
          min-width: 340px;
          max-width: 440px;
          opacity: 0;
          transform: translateY(10px);
          transition: opacity 0.5s ease, transform 0.5s ease;
        ">
          <div id="tl-flow" style="font-size: 14px; margin-bottom: 6px; font-weight: 600;"></div>
          <div id="tl-sources" style="font-size: 9px; color: #506070; margin-bottom: 8px;"></div>
          <div id="tl-headlines" style="
            font-size: 9px;
            margin-bottom: 8px;
            padding-bottom: 8px;
            border-bottom: 1px solid rgba(255,255,255,0.04);
            opacity: 0.85;
            display: none;
          "></div>
          <div id="tl-metrics" style="display: flex; gap: 16px; font-size: 9px; opacity: 0.75;"></div>
          <div id="tl-explanation" style="
            font-size: 9px;
            color: #687888;
            font-style: italic;
            margin-top: 6px;
            opacity: 0.6;
            display: none;
          "></div>
        </div>

        <!-- Bottom center: progress bar -->
        <div id="tl-progress" style="
          position: absolute;
          bottom: 60px;
          left: 50%;
          transform: translateX(-50%);
          width: 300px;
          opacity: 0;
          transition: opacity 0.5s ease;
        ">
          <div style="
            display: flex;
            justify-content: space-between;
            font-size: 8px;
            letter-spacing: 1px;
            color: #506070;
            margin-bottom: 4px;
          ">
            <span id="tl-time-start"></span>
            <span id="tl-time-end"></span>
          </div>
          <div style="
            width: 100%;
            height: 2px;
            background: rgba(255,255,255,0.06);
            border-radius: 1px;
            overflow: hidden;
          ">
            <div id="tl-progress-bar" style="
              width: 0%;
              height: 100%;
              background: linear-gradient(90deg, rgba(0,255,204,0.8), rgba(0,255,204,0.3));
              border-radius: 1px;
              transition: width 0.1s linear;
            "></div>
          </div>
        </div>

        <!-- Bottom right: summary stats -->
        <div id="tl-stats" style="
          position: absolute;
          bottom: 100px;
          right: 30px;
          text-align: right;
          opacity: 0;
          transition: opacity 0.5s ease;
        ">
          <div style="font-size: 8px; letter-spacing: 2px; color: #506070; text-transform: uppercase;">Timelapse Summary</div>
          <div id="tl-stats-content" style="
            font-size: 11px;
            color: #c0c8d0;
            margin-top: 6px;
            line-height: 1.8;
          "></div>
        </div>

        <!-- Controls -->
        <div id="tl-controls" style="
          position: absolute;
          bottom: 20px;
          left: 50%;
          transform: translateX(-50%);
          display: flex;
          gap: 12px;
          pointer-events: auto;
          z-index: 210;
          opacity: 0;
          transition: opacity 0.5s ease;
        ">
          <button id="tl-btn-playpause" style="
            background: rgba(0, 255, 204, 0.1);
            border: 1px solid rgba(0, 255, 204, 0.3);
            color: #00ffcc;
            font-family: inherit;
            font-size: 10px;
            letter-spacing: 1px;
            padding: 6px 16px;
            border-radius: 3px;
            cursor: pointer;
            text-transform: uppercase;
          ">Pause</button>
          <button id="tl-btn-restart" style="
            background: rgba(255, 255, 255, 0.05);
            border: 1px solid rgba(255, 255, 255, 0.15);
            color: #8090a0;
            font-family: inherit;
            font-size: 10px;
            letter-spacing: 1px;
            padding: 6px 16px;
            border-radius: 3px;
            cursor: pointer;
            text-transform: uppercase;
          ">Restart</button>
          <button id="tl-btn-exit" style="
            background: rgba(255, 255, 255, 0.05);
            border: 1px solid rgba(255, 255, 255, 0.15);
            color: #8090a0;
            font-family: inherit;
            font-size: 10px;
            letter-spacing: 1px;
            padding: 6px 16px;
            border-radius: 3px;
            cursor: pointer;
            text-transform: uppercase;
          ">Exit</button>
        </div>
      </div>
    `

    const globeContainer = this._c.element
    globeContainer.style.position = 'relative'
    globeContainer.appendChild(overlay)
    this._overlay = overlay

    document.getElementById('tl-btn-playpause').addEventListener('click', () => this._togglePause())
    document.getElementById('tl-btn-restart').addEventListener('click', () => this._restart())
    document.getElementById('tl-btn-exit').addEventListener('click', () => this.exit())

    const state = this._state
    if (state && state.segments.length > 0) {
      const first = state.segments[0]
      const last = state.segments[state.segments.length - 1]
      const startEl = document.getElementById('tl-time-start')
      const endEl = document.getElementById('tl-time-end')
      if (startEl) startEl.textContent = this._formatDate(first._timestamp)
      if (endEl) endEl.textContent = this._formatDate(last._timestamp)
    }

    const ctx = this._context
    const routeNameEl = document.getElementById('tl-route-name')
    if (ctx.mode === 'story' && routeNameEl) {
      const route = (this._c._allRoutes || []).find(r =>
        String(r.routeId || r.id) === String(ctx.routeId)
      )
      const headline = route?.headline || route?.sourceHeadline || `Route ${ctx.routeId}`
      routeNameEl.textContent = headline
      const headerEl = document.getElementById('tl-header')
      if (headerEl) {
        const modeLabel = headerEl.querySelector('div')
        if (modeLabel) modeLabel.innerHTML = '&#9654; STORY MODE &#9664;'
      }
    }

    requestAnimationFrame(() => {
      ['tl-header', 'tl-event-card', 'tl-progress', 'tl-stats', 'tl-controls'].forEach(id => {
        const el = document.getElementById(id)
        if (el) el.style.opacity = '1'
      })
    })
  }

  _formatDate(timestamp) {
    if (!timestamp) return ''
    const d = new Date(timestamp)
    return d.toLocaleDateString('en-US', { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' })
  }

  _updateOverlay(segment, state) {
    const framingColor = getFramingColor(segment.framingShift)

    const flowEl = document.getElementById('tl-flow')
    if (flowEl) {
      flowEl.innerHTML = `
        <span style="color: #b0c4d8;">${segment.sourceCountry || '?'}</span>
        <span style="color: #404850; margin: 0 8px;">&rarr;</span>
        <span style="color: ${framingColor};">${segment.targetCountry || '?'}</span>
      `
    }

    const srcEl = document.getElementById('tl-sources')
    if (srcEl) {
      srcEl.textContent = `${segment.sourceName || '?'} \u2192 ${segment.targetSourceName || '?'}`
    }

    const hdlEl = document.getElementById('tl-headlines')
    if (hdlEl && segment.sourceHeadline && segment.targetHeadline) {
      hdlEl.innerHTML = `
        <div style="color: #b0c4d8; margin-bottom: 3px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; max-width: 400px;">&#9654; ${segment.sourceHeadline}</div>
        <div style="color: ${framingColor}; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; max-width: 400px;">&#9654; ${segment.targetHeadline}</div>
      `
      hdlEl.style.display = 'block'
    } else if (hdlEl) {
      hdlEl.style.display = 'none'
    }

    const metEl = document.getElementById('tl-metrics')
    if (metEl) {
      const intensity = segment.driftIntensity || 0
      const driftLevel = intensity > 0.7 ? 'CRITICAL' :
                         intensity > 0.4 ? 'SIGNIFICANT' :
                         intensity > 0.15 ? 'MODERATE' : 'MINIMAL'
      const driftColor = intensity > 0.7 ? '#ff2d2d' :
                         intensity > 0.4 ? '#ff8c00' :
                         intensity > 0.15 ? '#ffd700' : '#8898a8'
      const similarity = Math.round((segment.semanticSimilarity || 0))

      metEl.innerHTML = `
        <div>
          <div style="font-size: 8px; color: #506070; text-transform: uppercase; letter-spacing: 1px;">Framing</div>
          <div style="color: ${framingColor}; font-weight: 600;">${(segment.framingShift || 'unknown').toUpperCase()}</div>
        </div>
        <div>
          <div style="font-size: 8px; color: #506070; text-transform: uppercase; letter-spacing: 1px;">Drift</div>
          <div style="color: ${driftColor}; font-weight: 600;">${driftLevel}</div>
        </div>
        <div>
          <div style="font-size: 8px; color: #506070; text-transform: uppercase; letter-spacing: 1px;">Sentiment</div>
          <div>${segment.sentimentShift || 'N/A'}</div>
        </div>
        <div>
          <div style="font-size: 8px; color: #506070; text-transform: uppercase; letter-spacing: 1px;">Match</div>
          <div style="color: ${similarity > 85 ? '#38bdf8' : '#ffd700'};">${similarity}%</div>
        </div>
      `
    }

    const expEl = document.getElementById('tl-explanation')
    if (expEl && segment.framingExplanation) {
      expEl.textContent = `"${segment.framingExplanation}"`
      expEl.style.display = 'block'
    } else if (expEl) {
      expEl.style.display = 'none'
    }

    const statsEl = document.getElementById('tl-stats-content')
    if (statsEl) {
      const countries = new Set()
      state.activeArcs.forEach(a => {
        if (a.sourceCountry) countries.add(a.sourceCountry)
        if (a.targetCountry) countries.add(a.targetCountry)
      })
      const driftValues = state.activeArcs.map(a => a.driftIntensity || 0)
      const maxDrift = driftValues.length > 0 ? Math.max(...driftValues) : 0
      const driftLabel = maxDrift > 0.7 ? 'CRITICAL' : maxDrift > 0.4 ? 'HIGH' : 'MODERATE'
      const driftColor = maxDrift > 0.7 ? '#ff2d2d' : maxDrift > 0.4 ? '#ff8c00' : '#ffd700'

      statsEl.innerHTML = `
        <div>${state.activeArcs.length} narrative hops</div>
        <div>${countries.size} countries involved</div>
        <div>Peak drift: <span style="color: ${driftColor};">${driftLabel}</span></div>
      `
    }

    const card = document.getElementById('tl-event-card')
    if (card) {
      card.style.opacity = '1'
      card.style.transform = 'translateY(0)'
    }
  }

  _updateProgress(state) {
    const progBar = document.getElementById('tl-progress-bar')
    if (progBar) {
      progBar.style.width = `${Math.round(state.currentTime * 100)}%`
    }
  }

  // ---- CONTROLS ----

  _togglePause() {
    const state = this._state
    if (!state) return

    state.playing = !state.playing
    const btn = document.getElementById('tl-btn-playpause')

    if (state.playing) {
      const pausedDuration = performance.now() - state._pausedAt
      state.startedAt += pausedDuration
      if (btn) btn.textContent = 'Pause'
      this._frame()
    } else {
      state._pausedAt = performance.now()
      if (btn) btn.textContent = 'Play'
    }
  }

  _restart() {
    const ctx = this._state
      ? { mode: this._state._mode, routeId: this._state._routeId }
      : this._context
    this.exit()
    this._context = ctx
    setTimeout(() => this._start(), 300)
  }

  exit() {
    const state = this._state
    if (state) state.playing = false
    this._state = null

    ['tl-header', 'tl-event-card', 'tl-progress', 'tl-stats', 'tl-controls'].forEach(id => {
      const el = document.getElementById(id)
      if (el) el.style.opacity = '0'
    })

    window.dispatchEvent(new CustomEvent("veritas:timelapseState", {
      detail: { active: false }
    }))

    setTimeout(() => {
      this._restore()
      if (this._overlay) {
        this._overlay.remove()
        this._overlay = null
      }
    }, 600)
  }

  _exitImmediate() {
    const state = this._state
    if (state) state.playing = false
    this._state = null

    this._restore()
    if (this._overlay) {
      this._overlay.remove()
      this._overlay = null
    }

    window.dispatchEvent(new CustomEvent("veritas:timelapseState", {
      detail: { active: false }
    }))
  }

  _end() {
    const state = this._state
    if (state) state.playing = false

    const btn = document.getElementById('tl-btn-playpause')
    if (btn) {
      btn.textContent = 'Replay'
      btn.onclick = () => {
        btn.onclick = null
        this._restart()
      }
    }
  }

  _restore() {
    if (!this._globe || !this._preState) return

    const state = this._preState
    const c = this._c

    this._globe
      .arcColor(d => c._arcColorFn(d))
      .arcStroke(d => this.arcStrokeDefault(d))
      .arcDashAnimateTime(d => {
        if (d.arcDashAnimateTime != null) return d.arcDashAnimateTime
        if (d.driftIntensity != null) return Math.round(4000 - (d.driftIntensity * 2800))
        return d.tier === 1 ? 2500 : 0
      })
      .arcDashLength(d => {
        if (d.arcDashLength != null) return d.arcDashLength
        if (d.driftIntensity != null) {
          const f = d.framingShift || 'original'
          if (f === 'original') return 1
          if (f === 'neutralized') return 0.6
          if (f === 'amplified') return 0.4
          if (f === 'distorted') return 0.25
          return 1
        }
        return d.tier === 1 ? 0.5 : 0
      })
      .arcDashGap(d => {
        if (d.arcDashGap != null) return d.arcDashGap
        if (d.driftIntensity != null) {
          const f = d.framingShift || 'original'
          if (f === 'original') return 0
          if (f === 'neutralized') return 0.15
          if (f === 'amplified') return 0.2
          if (f === 'distorted') return 0.25
          return 0
        }
        return d.tier === 1 ? 0.15 : 0
      })

    this._globe
      .hexBinPointsData(c._cloneLayer(state.hexBinPointsData || []))
      .arcsData(c._cloneLayer(state.arcsData || []))
      .ringsData(c._cloneLayer(state.ringsData || []))

    if (state.pointOfView) this._globe.pointOfView(state.pointOfView, 1000)

    const controls = this._globe.controls()
    controls.autoRotate = state.autoRotate ?? true
    controls.autoRotateSpeed = state.autoRotateSpeed ?? 0.4

    if (c._packetAnimator?.group) c._packetAnimator.group.visible = state.packetVisible !== false
    c._packetAnimator?.update()

    this._preState = null
  }
}
