import { Controller } from "@hotwired/stimulus"
import consumer from "channels/consumer"

const THREAT_RING = {
  3: { color: "#ff3a5e", maxRadius: 7,  propagationSpeed: 3.0, repeatPeriod: 700  },
  2: { color: "#ffc107", maxRadius: 5,  propagationSpeed: 1.8, repeatPeriod: 1200 },
  1: { color: "#00ff87", maxRadius: 3,  propagationSpeed: 0.8, repeatPeriod: 2200 }
}

export default class extends Controller {
  static values = { dataUrl: String }

  connect() {
    this.element.__controller = this
    this._currentPerspective = localStorage.getItem("veritas:perspective") || "all"
    this._currentTopic       = localStorage.getItem("veritas:topic")       || null
    this._currentTimestamp   = null
    this._pointHovered       = false
    this._arcHovered         = false
    this._abortController    = null
    this._heatmapActive      = false
    this._heatmapBaseData    = []
    this._heatmapClusters    = []
    this._heatmapPulseId     = null
    this._heatmapTooltipEl   = null
    this._lastHoveredCluster = null
    this._flyToHandler          = (e) => this._onFlyToEvent(e)
    this._perspectiveHandler    = (e) => this._onPerspectiveChange(e)
    this._topicHandler          = (e) => this._onTopicFilter(e)
    this._timelineHandler       = (e) => this._onTimelineChange(e)
    this._searchHandler         = (e) => this._onSearchEvent(e)
    this._searchClearHandler    = (e) => this._onSearchClearEvent(e)
    this._breakingAlertHandler  = (e) => this._onBreakingAlert(e)
    this._viewModeHandler       = (e) => this._onViewModeChanged(e)
    this._heatmapToggleHandler  = (e) => this._onHeatmapToggle(e)
    this._dayNightToggleHandler  = (e) => this._onDayNightToggle(e)
    this._modeChangedHandler     = (e) => this._onModeChanged(e)
    this._isolateToggleHandler   = (e) => this._onIsolateToggle(e)
    this._journeyActivateHandler = (e) => this._onJourneyActivated(e)
    this._journeyEndedHandler    = (e) => this._onJourneyEnded(e)
    this._routeMenuClickHandler  = (e) => this._handleRouteMenuDocumentClick(e)
    this._hideIsolated           = false
    this._journeyActive          = false
    this._allRoutes              = []
    this._preJourneyState        = null
    this._routeChoiceMenu        = null
    this._routeMenuOpenedAt      = 0
    window.addEventListener("veritas:flyTo",             this._flyToHandler)
    window.addEventListener("veritas:perspectiveChange", this._perspectiveHandler)
    window.addEventListener("veritas:topicFilter",       this._topicHandler)
    window.addEventListener("veritas:timelineChange",    this._timelineHandler)
    window.addEventListener("veritas:search",            this._searchHandler)
    window.addEventListener("veritas:searchClear",       this._searchClearHandler)
    window.addEventListener("veritas:breakingAlert",     this._breakingAlertHandler)
    window.addEventListener("veritas:view-mode-changed", this._viewModeHandler)
    window.addEventListener("veritas:heatmapToggle",     this._heatmapToggleHandler)
    window.addEventListener("veritas:dayNightToggle",    this._dayNightToggleHandler)
    window.addEventListener("veritas:mode-changed",      this._modeChangedHandler)
    window.addEventListener("veritas:isolateToggle",     this._isolateToggleHandler)
    window.addEventListener("veritas:bloomActive",       this._journeyActivateHandler)
    window.addEventListener("veritas:chronicleActive",   this._journeyActivateHandler)
    window.addEventListener("veritas:journeyEnded",      this._journeyEndedHandler)
    document.addEventListener("click",                   this._routeMenuClickHandler)
    this._initGlobe()
    this._subscription = consumer.subscriptions.create("GlobeChannel", {
      received:     (data) => this._onBroadcast(data),
      rejected:     ()     => console.error("[VERITAS Globe] WebSocket subscription rejected")
    })

    // Packet animation state
    this._packetGroup = null
    this._packets = []
    this._animationFrameId = null
  }

  disconnect() {
    delete this.element.__controller
    this._subscription?.unsubscribe()
    window.removeEventListener("veritas:flyTo",             this._flyToHandler)
    window.removeEventListener("veritas:perspectiveChange", this._perspectiveHandler)
    window.removeEventListener("veritas:topicFilter",       this._topicHandler)
    window.removeEventListener("veritas:timelineChange",    this._timelineHandler)
    window.removeEventListener("veritas:search",            this._searchHandler)
    window.removeEventListener("veritas:searchClear",       this._searchClearHandler)
    window.removeEventListener("veritas:breakingAlert",     this._breakingAlertHandler)
    window.removeEventListener("veritas:view-mode-changed", this._viewModeHandler)
    window.removeEventListener("veritas:heatmapToggle",     this._heatmapToggleHandler)
    window.removeEventListener("veritas:dayNightToggle",    this._dayNightToggleHandler)
    window.removeEventListener("veritas:mode-changed",      this._modeChangedHandler)
    window.removeEventListener("veritas:isolateToggle",     this._isolateToggleHandler)
    window.removeEventListener("veritas:bloomActive",       this._journeyActivateHandler)
    window.removeEventListener("veritas:chronicleActive",   this._journeyActivateHandler)
    window.removeEventListener("veritas:journeyEnded",      this._journeyEndedHandler)
    document.removeEventListener("click",                   this._routeMenuClickHandler)
    clearTimeout(this._rotateTimer)
    if (this._heatmapPulseId) clearInterval(this._heatmapPulseId)
    if (this._heatmapTooltipEl) this._heatmapTooltipEl.remove()
    if (this._onMouseMove) this.element.removeEventListener('mousemove', this._onMouseMove)
    if (this._onMouseLeave) this.element.removeEventListener('mouseleave', this._onMouseLeave)
    if (this._resizeObserver) this._resizeObserver.disconnect()
    if (this._globe) {
      cancelAnimationFrame(this._animFrame)
      this._globe._destructor && this._globe._destructor()
    }
    // Clean up packet animation
    if (this._animationFrameId) {
      cancelAnimationFrame(this._animationFrameId)
    }
    if (this._packetGroup && this._globe) {
      this._globe.scene().remove(this._packetGroup)
    }
    this._hideRouteChoiceMenu()
  }

  get globe() {
    return this._globe
  }

  captureJourneyState() {
    if (!this._globe) return null

    const controls = this._globe.controls()

    return {
      arcsData: this._cloneLayer(this._globe.arcsData() || []),
      pointsData: this._cloneLayer(this._globe.pointsData() || []),
      ringsData: this._cloneLayer(this._globe.ringsData() || []),
      pointOfView: { ...(this._globe.pointOfView?.() || { lat: 20, lng: 10, altitude: 2.5 }) },
      autoRotate: controls.autoRotate,
      autoRotateSpeed: controls.autoRotateSpeed,
      packetVisible: this._packetGroup ? this._packetGroup.visible !== false : true
    }
  }

  restoreJourneyState(state = this._preJourneyState) {
    if (!this._globe || !state) return

    const controls = this._globe.controls()
    controls.autoRotate = state.autoRotate ?? true
    controls.autoRotateSpeed = state.autoRotateSpeed ?? 0.4

    this._globe
      .pointsData(this._cloneLayer(state.pointsData || []))
      .arcsData(this._cloneLayer(state.arcsData || []))
      .ringsData(this._cloneLayer(state.ringsData || []))

    if (state.pointOfView) this._globe.pointOfView(state.pointOfView, 900)
    if (this._packetGroup) this._packetGroup.visible = state.packetVisible !== false
    if (this._globe) this._updatePackets()
  }

  getRoute(routeId) {
    return (this._allRoutes || []).find((route) => String(route.routeId || route.id) === String(routeId))
  }

  getScreenPosition(lat, lng) {
    if (!this._globe) return null

    const coords = this._globe.getScreenCoords(lat, lng)
    if (!coords) return null

    return { x: coords.x, y: coords.y }
  }

  // -------------------------------------------------------
  // Private
  // -------------------------------------------------------

  async _initGlobe() {
    const Globe = (await import("globe.gl")).default

    const container = this.element

    this._globe = Globe()
      .globeImageUrl("//unpkg.com/three-globe/example/img/earth-blue-marble.jpg")
      .bumpImageUrl("//unpkg.com/three-globe/example/img/earth-topology.png")
      .backgroundImageUrl("//unpkg.com/three-globe/example/img/night-sky.png")
      .width(container.clientWidth)
      .height(container.clientHeight)
      .atmosphereColor("#00f0ff")
      .atmosphereAltitude(0.25)
      // Points layer (articles)
      .pointAltitude("size")
      .pointColor(d => this._pointColorForPerspective(d))
      .pointRadius(d => d.radius || 0.35)
      // NOTE: pointsMerge disabled — required for individual point click events
      .onPointHover(point => this._onPointHover(point))
      .onPointClick(point => this._onPointClicked(point))
      // Arcs layer (narrative arcs)
      // tier 1 (top 5 by strength): thick, animated dash, full opacity
      // tier 2 (next 10): thin, solid, 35% opacity
      // no tier (legacy fallback arcs): use thickness field
      .arcColor(d => this._arcColorForPerspective(d))
      .arcDashLength(d => d.arcDashLength != null ? d.arcDashLength : (d.tier === 1 ? 0.5 : 0))
      .arcDashGap(d => d.arcDashGap != null ? d.arcDashGap : (d.tier === 1 ? 0.15 : 0))
      .arcDashAnimateTime(d => d.arcDashAnimateTime != null ? d.arcDashAnimateTime : (d.tier === 1 ? 2500 : 0))
      .arcStroke(d => {
        if (d.arcStroke != null) return d.arcStroke
        if (d.tier === 1) return 2.5
        if (d.tier === 2) return 0.8
        return d.thickness || 0.5
      })
      .onArcHover(arc => this._onArcHover(arc))
      .onArcClick(arc => this._onArcClicked(arc))
      // Tooltips
      .pointLabel(d => `
        <div style="
          background: rgba(10,12,20,0.92);
          border: 1px solid rgba(0,240,255,0.3);
          border-radius: 4px;
          padding: 8px 12px;
          font-family: 'JetBrains Mono', monospace;
          font-size: 11px;
          color: #e0e6ed;
          max-width: 280px;
          line-height: 1.4;
          box-shadow: 0 0 20px rgba(0,240,255,0.15);
        ">
          <div style="color:#00f0ff;font-size:9px;letter-spacing:0.1em;margin-bottom:4px;">${d.source || 'UNKNOWN SOURCE'}</div>
          <div style="font-weight:600;">${d.headline || 'No headline'}</div>
          <div style="color:#6b7280;font-size:9px;margin-top:4px;">
            ${d.lat.toFixed(2)}°, ${d.lng.toFixed(2)}°
          </div>
        </div>
      `)
      .arcLabel(d => {
        const isSegment = d.sourceName !== undefined || d.targetSourceName !== undefined
        const segmentInfo = isSegment ? `
          <div style="color:#a78bfa;font-size:8px;letter-spacing:0.1em;margin-bottom:2px;text-transform:uppercase;">
            HOP ${d.segmentIndex + 1} of ${d.totalSegments}
          </div>
          <div style="font-size:10px;margin-bottom:4px;">
            ${d.sourceName || 'Unknown'} → ${d.targetSourceName || 'Unknown'}
          </div>
        ` : ''
        return `
        <div style="
          background: rgba(10,12,20,0.92);
          border: 1px solid rgba(0,240,255,0.3);
          border-radius: 4px;
          padding: 8px 12px;
          font-family: 'JetBrains Mono', monospace;
          font-size: 11px;
          color: #e0e6ed;
          line-height: 1.4;
          box-shadow: 0 0 20px rgba(0,240,255,0.15);
        ">
          <div style="color:#00f0ff;font-size:9px;letter-spacing:0.1em;margin-bottom:4px;">
            ${isSegment ? 'NARRATIVE SEGMENT' : 'NARRATIVE ARC'}
          </div>
          ${segmentInfo}
          <div>${d.originCountry || 'Unknown'} → ${d.targetCountry || 'Unknown'}</div>
          <div style="margin-top:4px;font-weight:600;">${d.headline || 'Linked intelligence signal'}</div>
          <div style="color:#6b7280;font-size:9px;margin-top:4px;">${d.source || 'UNKNOWN SOURCE'}</div>
          ${d.publishedAt ? `<div style="color:#6b7280;font-size:8px;margin-top:2px;">${new Date(d.publishedAt).toLocaleString()}</div>` : ''}
          ${d.strength != null ? `
          <div style="margin-top:6px;padding-top:4px;border-top:1px solid rgba(0,240,255,0.2);display:flex;justify-content:space-between;align-items:center;">
            <span style="color:#22c55e;font-size:8px;letter-spacing:0.08em;">SEMANTIC MATCH</span>
            <span style="color:#22c55e;font-size:10px;font-weight:700;">${Math.round(d.strength * 100)}%</span>
          </div>` : ''}
        </div>
      `})
      // Heatmap layer (threat thermal overlay)
      // heatmapsData = [ pointsArray ] — each dataset IS the points array (identity accessor)
      .heatmapsData([])
      .heatmapPointLat('lat')
      .heatmapPointLng('lng')
      .heatmapPointWeight('weight')
      .heatmapTopAltitude(0.12)
      .heatmapBandwidth(3.2)
      // accessorFn treats functions as per-datum accessors, so we wrap
      // the color fn in an outer function that returns the actual color fn
      .heatmapColorFn(() => t => {
        // Predator-vision thermal: transparent → indigo → red → orange → white-hot
        if (t < 0.05) return 'rgba(0,0,0,0)'
        const a = Math.min(1, t * 1.8)
        if (t < 0.2) return `rgba(40,0,${Math.round(120 + t * 400)},${a})`
        if (t < 0.45) return `rgba(${Math.round((t - 0.2) * 1020)},0,${Math.round(200 - (t - 0.2) * 600)},${a})`
        if (t < 0.7) return `rgba(255,${Math.round((t - 0.45) * 440)},0,${Math.min(1, a + 0.1)})`
        return `rgba(255,${Math.round(110 + (t - 0.7) * 483)},${Math.round((t - 0.7) * 400)},1)`
      })
      .heatmapsTransitionDuration(800)
      // Threat rings layer (pulsing radar rings per region)
      .ringsData([])
      .ringLat("lat")
      .ringLng("lng")
      .ringColor(d => t => {
        const cfg = THREAT_RING[d.threat] || THREAT_RING[1]
        const hex = cfg.color
        const r   = parseInt(hex.slice(1, 3), 16)
        const g   = parseInt(hex.slice(3, 5), 16)
        const b   = parseInt(hex.slice(5, 7), 16)
        return `rgba(${r},${g},${b},${Math.max(0, (1 - t) * 0.75)})`
      })
      .ringMaxRadius("maxRadius")
      .ringPropagationSpeed("propagationSpeed")
      .ringRepeatPeriod("repeatPeriod")
      (container)

    // Add scene lighting — sunlight on the visible hemisphere
    this._isDay = true
    this._setupLighting()

    const controls = this._globe.controls()
    controls.autoRotate = true
    controls.autoRotateSpeed = 0.4
    controls.enableZoom = true
    controls.minDistance = 150
    controls.maxDistance = 500

    this._globe.pointOfView({ lat: 20, lng: 10, altitude: 2.5 }, 0)

    await this._loadData()

    this._resizeObserver = new ResizeObserver(() => {
      this._globe.width(container.clientWidth).height(container.clientHeight)
    })
    this._resizeObserver.observe(container)

    // Mousemove → heatmap tooltip (raycasts globe surface for lat/lng)
    this._onMouseMove = (e) => this._handleHeatmapHover(e, container)
    this._onMouseLeave = () => this._hideHeatmapTooltip()
    container.addEventListener('mousemove', this._onMouseMove)
    container.addEventListener('mouseleave', this._onMouseLeave)
  }

  async _setupLighting() {
    const scene = this._globe?.scene()
    if (!scene) return

    try {
      const THREE = await import("three")

      // Remove default lights for full control
      const toRemove = []
      scene.traverse(obj => { if (obj.isLight) toRemove.push(obj) })
      toRemove.forEach(l => scene.remove(l))

      // Strong ambient — ensures no pitch-black areas
      scene.add(new THREE.AmbientLight(0xffffff, 2.0))

      // Primary sun — warm white from upper-right
      const sun = new THREE.DirectionalLight(0xffffff, 1.8)
      sun.position.set(1, 1, 1).normalize()
      scene.add(sun)

      // Fill light from opposite side — prevents harsh shadows
      const fill = new THREE.DirectionalLight(0xffffff, 1.2)
      fill.position.set(-1, -1, 1).normalize()
      scene.add(fill)

      // Boost mesh materials so the texture pops
      scene.traverse(obj => {
        if (obj.isMesh && obj.material) {
          obj.material.lightMapIntensity = 2
          obj.material.needsUpdate = true
        }
      })
    } catch (e) {
      console.warn("[VERITAS Globe] Could not set up lighting:", e)
    }
  }

  _onDayNightToggle() {
    this._isDay = !this._isDay

    if (this._globe) {
      const texture = this._isDay
        ? "//unpkg.com/three-globe/example/img/earth-blue-marble.jpg"
        : "//unpkg.com/three-globe/example/img/earth-night.jpg"
      this._globe.globeImageUrl(texture)
      this._applyLighting()
    }

    window.dispatchEvent(new CustomEvent("veritas:dayNightState", {
      detail: { isDay: this._isDay }
    }))
  }

  async _applyLighting() {
    const scene = this._globe?.scene()
    if (!scene) return

    try {
      const THREE = await import("three")

      // Remove all existing lights
      const toRemove = []
      scene.traverse(obj => { if (obj.isLight) toRemove.push(obj) })
      toRemove.forEach(l => scene.remove(l))

      if (this._isDay) {
        // Bright daytime lighting
        scene.add(new THREE.AmbientLight(0xffffff, 2.0))
        const sun = new THREE.DirectionalLight(0xffffff, 1.8)
        sun.position.set(1, 1, 1).normalize()
        scene.add(sun)
        const fill = new THREE.DirectionalLight(0xffffff, 1.2)
        fill.position.set(-1, -1, 1).normalize()
        scene.add(fill)
      } else {
        // Night mode — the earth-night.jpg texture has bright city lights on
        // a dark surface. We need strong ambient so those lights show through,
        // but no harsh directional so the overall feel stays dark/moody.
        scene.add(new THREE.AmbientLight(0xffffff, 1.6))
        const soft = new THREE.DirectionalLight(0x8899bb, 0.4)
        soft.position.set(0, 1, 1).normalize()
        scene.add(soft)
      }

      // Update materials
      scene.traverse(obj => {
        if (obj.isMesh && obj.material) {
          obj.material.lightMapIntensity = this._isDay ? 2 : 1.5
          obj.material.needsUpdate = true
        }
      })
    } catch (e) {
      console.warn("[VERITAS Globe] Could not apply day/night lighting:", e)
    }
  }

  _loadData() {
    if (this._journeyActive) return Promise.resolve()
    return this._fetchAndRender()
  }

  async _fetchAndRender() {
    if (this._journeyActive) return

    // Cancel any in-flight request before starting a new one
    this._abortController?.abort()
    this._abortController = new AbortController()
    const signal = this._abortController.signal

    try {
      const params = new URLSearchParams()
      if (this._currentTopic) {
        params.set("topic", this._currentTopic)
      }
      if (this._currentTimestamp) {
        params.set("to", this._currentTimestamp)
      }
      // ARCWEAVER 2.0: Load multi‑segment routes instead of simple arcs
      params.set("view", "segments")

      const query = params.toString()
      const url   = query ? `${this.dataUrlValue}?${query}` : this.dataUrlValue
      const response = await fetch(url, { signal })
      const data     = await response.json()

      const rings = (data.regions || []).map(r => ({
        ...r,
        ...(THREAT_RING[parseInt(r.threat, 10)] || THREAT_RING[1])
      }))

      // Store heatmap base data + cluster summaries for thermal layer
      this._heatmapBaseData  = data.heatmap || []
      this._heatmapClusters  = data.heatmapClusters || []

      // Store full datasets for isolate filter
      this._allPoints = data.points || []
      this._allArcs   = data.arcs || []
      this._allRoutes = data.routes || []
      this._allRoutes = data.routes || []

      if (this._heatmapActive) {
        this._globe.heatmapsData([this._heatmapBaseData])
      } else {
        let visiblePoints = this._allPoints
        if (this._hideIsolated) {
          const connectedIds = new Set()
          this._allArcs.forEach(arc => { if (arc.articleId) connectedIds.add(arc.articleId) })
          visiblePoints = this._allPoints.filter(p => connectedIds.has(p.id))
        }

        this._globe
          .pointsData(visiblePoints)
          .arcsData(this._allArcs)
          .ringsData(rings)

        if (this._globe) this._updatePackets()
      }
    } catch (err) {
      if (err.name === 'AbortError') return  // stale request superseded by newer one
      console.error("[VERITAS Globe] Failed to load globe data:", err)
    }
  }

  _updatePackets() {
    if (this._journeyActive) return
    if (!this._globe || !window.THREE) {
      console.warn("[VERITAS Globe] THREE.js not available, skipping packet animation")
      return
    }

    const scene = this._globe.scene()
    if (!scene) return

    // Create packet group if it doesn't exist
    if (!this._packetGroup) {
      this._packetGroup = new window.THREE.Group()
      scene.add(this._packetGroup)
    }

    // Clear existing packets
    this._packetGroup.clear()
    this._packets.length = 0

    // Get current arcs (segments)
    const arcs = this._globe.arcsData()
    if (!arcs || arcs.length === 0) return

    // Create a packet for each segment
    arcs.forEach((segment, index) => {
      // Create a small sphere
      const geometry = new window.THREE.SphereGeometry(0.08, 8, 8)
      // Convert color array to a single string if needed (fallback simple arcs use array for gradient)
      let packetColor = segment.color || '#00f0ff'
      if (Array.isArray(packetColor)) {
        packetColor = packetColor[0]
      }

      const material = new window.THREE.MeshBasicMaterial({
        color: packetColor,
        transparent: true,
        opacity: 0.9
      })
      const sphere = new window.THREE.Mesh(geometry, material)
      
      // Store packet data
      this._packets.push({
        segment,
        mesh: sphere,
        progress: Math.random() * 0.8 + 0.1, // random starting position
        speed: this._calculatePacketSpeed(segment)
      })
      
      this._packetGroup.add(sphere)
    })

    // Start animation if not already running
    if (!this._animationFrameId) {
      this._animatePackets()
    }
  }

  _calculatePacketSpeed(segment) {
    // Base speed: pixels per second? We'll use a constant for now
    // Adjust based on delaySeconds: longer delay = slower speed
    const baseSpeed = 0.00015
    const delayFactor = segment.delaySeconds ? Math.max(0.5, Math.min(2.0, 1800 / segment.delaySeconds)) : 1.0
    return baseSpeed * delayFactor
  }

  _animatePackets() {
    if (!this._globe || !this._packetGroup) return

    const now = Date.now()
    
    this._packets.forEach(packet => {
      // Update progress based on speed
      packet.progress += packet.speed
      if (packet.progress > 1.0) packet.progress = 0.0
      
      // Interpolate position along the segment
      const startLat = packet.segment.startLat
      const startLng = packet.segment.startLng
      const endLat = packet.segment.endLat
      const endLng = packet.segment.endLng
      
      const lat = startLat + (endLat - startLat) * packet.progress
      const lng = startLng + (endLng - startLng) * packet.progress
      
      // Convert lat/lng to 3D position on globe surface (slightly elevated)
      const radius = this._globe.getGlobeRadius() || 100
      const phi = (90 - lat) * Math.PI / 180
      const theta = (lng + 180) * Math.PI / 180
      
      const x = -radius * Math.sin(phi) * Math.cos(theta)
      const y = radius * Math.cos(phi)
      const z = radius * Math.sin(phi) * Math.sin(theta)
      
      // Position packet 2% above globe surface
      const elevation = 1.02
      packet.mesh.position.set(x * elevation, y * elevation, z * elevation)
    })
    
    // Continue animation
    this._animationFrameId = requestAnimationFrame(() => this._animatePackets())
  }

  _onPerspectiveChange(event) {
    this._currentPerspective = event.detail.slug || event.detail.perspectiveId || "all"
    localStorage.setItem("veritas:perspective", this._currentPerspective)
    if (this._journeyActive) return
    // Client-side only — re-apply color callbacks without re-fetching data
    if (this._globe && this._allPoints) {
      this._globe
        .pointsData([...this._allPoints])
        .arcsData([...this._allArcs || []])
    }
  }

  _pointColorForPerspective(d) {
    if (d?._journey) return d.color || '#00f0ff'
    const c = d.color || '#00f0ff'
    if (this._currentPerspective === 'all') return c
    return d.perspectiveSlug === this._currentPerspective ? c : this._hexToRgba(c, 0.12)
  }

  _arcColorForPerspective(d) {
    if (d?._journey) return d.color || '#00f0ff'
    const c = Array.isArray(d.color) ? d.color[0] : (d.color || '#00f0ff')
    const baseTierAlpha = d.tier === 2 ? 0.35 : 1.0
    if (this._currentPerspective === 'all') {
      return d.tier === 2 ? this._hexToRgba(c, 0.35) : c
    }
    const isActive = d.perspectiveSlug === this._currentPerspective
    return this._hexToRgba(c, isActive ? baseTierAlpha : 0.07)
  }

  _onTopicFilter(event) {
    this._currentTopic = event.detail.topic || null
    localStorage.setItem("veritas:topic", this._currentTopic || "")
    if (this._journeyActive) return
    this._loadData()
  }

  _onTimelineChange(event) {
    this._currentTimestamp = event.detail.toTimestamp
    if (this._journeyActive) return
    this._loadData()
  }

  _onPointClicked(point) {
    if (!point) return
    if (this._journeyActive) return
    this._flyTo(point.lat, point.lng)
    if (point.id) this._setActiveCard(point.id)
    if (point.id) this._visitArticle(point.id)
  }

  _onPointHover(point) {
    this._pointHovered = Boolean(point)
    this._syncAutoRotate()
  }

  _onArcClicked(arc) {
    if (!arc) return
    if (this._journeyActive) return

    if (arc.tier === 1 && arc.routeId) {
      this._showRouteChoiceMenu(arc)
      if (arc.articleId) this._setActiveCard(arc.articleId)
      return
    }

    const midLat = (arc.startLat + arc.endLat) / 2
    const midLng = (arc.startLng + arc.endLng) / 2
    this._flyTo(midLat, midLng, 2.0)
    if (arc.articleId) this._setActiveCard(arc.articleId)

    // Show hop details in timeline sidebar
    this._showHopDetails(arc)

    // Open Narrative DNA panel for this arc's source article
    if (arc.articleId) {
      window.dispatchEvent(new CustomEvent("veritas:openNarrativeDna", {
        detail: { articleId: arc.articleId }
      }))
    }
  }

  _onArcHover(arc) {
    if (this._journeyActive) return
    // Reset previous hover highlights
    if (this._lastHoveredArc && this._lastHoveredArc !== arc && this._packets) {
      this._packets.forEach(packet => {
        if (packet.segment === this._lastHoveredArc) {
          let packetColor = packet.segment.color || '#00f0ff'
          if (Array.isArray(packetColor)) {
            packetColor = packetColor[0]
          }
          packet.mesh.material.color.set(packetColor)
          packet.mesh.scale.set(1, 1, 1)
        }
      })
    }
    
    this._arcHovered = Boolean(arc)
    this._syncAutoRotate()
    
    // Highlight the segment on hover
    if (arc && this._packets) {
      this._packets.forEach(packet => {
        if (packet.segment === arc) {
          packet.mesh.material.color.set('#ffffff') // highlight white
          packet.mesh.scale.set(1.5, 1.5, 1.5)
        }
      })
    }
    
    this._lastHoveredArc = arc
  }

  _onFlyToEvent(event) {
    const { lat, lng, articleId } = event.detail
    this._flyTo(lat, lng)
    if (articleId) this._setActiveCard(articleId)
  }

  _onJourneyActivated(event) {
    if (!this._globe) return

    this._journeyActive = true
    this._preJourneyState = event.detail?.state || this._preJourneyState || this.captureJourneyState()
    this._hideRouteChoiceMenu()

    if (this._packetGroup) this._packetGroup.visible = false
    this._globe.arcsData([]).pointsData([]).ringsData([])
  }

  _onJourneyEnded(event) {
    this._journeyActive = false
    this._hideRouteChoiceMenu()
    this.restoreJourneyState(event.detail?.state || this._preJourneyState)
    this._preJourneyState = null
  }

  _showRouteChoiceMenu(arc) {
    const route = this.getRoute(arc.routeId)
    if (!route) return

    this._hideRouteChoiceMenu()

    const position = this.getScreenPosition(
      (arc.startLat + arc.endLat) / 2,
      (arc.startLng + arc.endLng) / 2
    )
    if (!position) return

    const menu = document.createElement("div")
    menu.className = "vt-route-choice-menu"
    menu.style.left = `${position.x}px`
    menu.style.top = `${position.y}px`
    menu.innerHTML = `
      <div class="vt-route-choice-header">${route.routeName || "Narrative Route"}</div>
      <button class="vt-route-choice-btn vt-route-choice-btn--bloom" type="button">◉ BLOOM</button>
      <button class="vt-route-choice-btn vt-route-choice-btn--chronicle" type="button">▶ CHRONICLE</button>
    `

    const [bloomButton, chronicleButton] = menu.querySelectorAll("button")
    bloomButton?.addEventListener("click", (clickEvent) => {
      clickEvent.stopPropagation()
      this._startJourneyFromRoute(route, "bloom")
    })
    chronicleButton?.addEventListener("click", (clickEvent) => {
      clickEvent.stopPropagation()
      this._startJourneyFromRoute(route, "chronicle")
    })

    this.element.appendChild(menu)
    this._routeChoiceMenu = menu
    this._routeMenuOpenedAt = Date.now()
  }

  _startJourneyFromRoute(route, mode) {
    this._hideRouteChoiceMenu()
    window.dispatchEvent(new CustomEvent("veritas:startJourney", {
      detail: {
        mode,
        routeId: route.routeId || route.id,
        route,
        segments: route.segments || []
      }
    }))
  }

  _hideRouteChoiceMenu() {
    if (this._routeChoiceMenu) this._routeChoiceMenu.remove()
    this._routeChoiceMenu = null
  }

  _handleRouteMenuDocumentClick(event) {
    if (!this._routeChoiceMenu) return
    if (Date.now() - this._routeMenuOpenedAt < 80) return
    if (this._routeChoiceMenu.contains(event.target)) return
    this._hideRouteChoiceMenu()
  }

  _onBreakingAlert(event) {
    const { lat, lng, severity, color } = event.detail
    if (!lat || !lng) return

    // Fly closer than normal — this is a priority target
    this._flyTo(lat, lng, 1.1)

    // Inject a surge ring that persists for 30s, then fades
    this._addSurgeRing(lat, lng, severity, color)
  }

  _addSurgeRing(lat, lng, severity, color) {
    if (!this._globe) return

    const ringColor = color || "#ff3a5e"
    const surgeRing = {
      lat, lng,
      color:             ringColor,
      maxRadius:         12,
      propagationSpeed:  4.5,
      repeatPeriod:      600
    }

    const current = this._globe.ringsData() || []
    this._globe.ringsData([...current, surgeRing])

    // Remove after 30s — alert window
    setTimeout(() => {
      const updated = (this._globe.ringsData() || []).filter(r => r !== surgeRing)
      this._globe.ringsData(updated)
    }, 30000)
  }

  _flyTo(lat, lng, altitude = 1.5) {
    if (!this._globe) return
    const controls = this._globe.controls()
    controls.autoRotate = false
    this._globe.pointOfView({ lat, lng, altitude }, 1200)
    clearTimeout(this._rotateTimer)
    this._rotateTimer = setTimeout(() => this._syncAutoRotate(), 6000)
  }

  _setActiveCard(articleId) {
    document.querySelectorAll('.veritas-feed-card').forEach(card => {
      card.classList.remove('is-active')
    })
    const card = document.querySelector(`.veritas-feed-card[data-article-id="${articleId}"]`)
    if (card) {
      card.classList.add('is-active')
      card.scrollIntoView({ behavior: 'smooth', block: 'nearest' })
    }
  }

  _visitArticle(articleId) {
    window.location.assign(`/articles/${articleId}`)
  }

  _syncAutoRotate() {
    if (!this._globe) return

    const controls = this._globe.controls()
    controls.autoRotate = !(this._pointHovered || this._arcHovered)
  }

  _showHopDetails(segment) {
    const container = document.getElementById('hop-details')
    const emptyMsg = document.querySelector('.hop-timeline-empty')
    if (!container || !emptyMsg) return

    // Hide empty message, show details container
    emptyMsg.classList.add('d-none')
    container.classList.remove('d-none')

    // Format date
    const publishedAt = segment.publishedAt ? new Date(segment.publishedAt) : null
    const dateStr = publishedAt ? publishedAt.toLocaleString() : 'Unknown'

    // Determine framing shift label and color
    const framingColor = segment.color || '#00f0ff'
    let framingLabel = 'Unknown'
    if (framingColor === '#22c55e') framingLabel = 'Original'
    else if (framingColor === '#f59e0b') framingLabel = 'Amplified'
    else if (framingColor === '#ef4444') framingLabel = 'Distorted'
    else if (framingColor === '#3b82f6') framingLabel = 'Neutralized'

    // Build HTML using Bootstrap/Veritas classes
    container.innerHTML = `
      <div class="veritas-feed-card mb-3">
        <div class="d-flex justify-content-between align-items-center mb-2">
          <span class="feed-source text-uppercase" style="font-size: 0.8rem; color: #00f0ff;">
            ${segment.routeName || 'Unnamed Route'}
          </span>
          <span class="badge bg-dark" style="font-size: 0.7rem;">
            Hop ${segment.segmentIndex + 1} of ${segment.totalSegments}
          </span>
        </div>
        
        <div class="d-flex justify-content-between align-items-center mb-3">
          <div class="text-center">
            <div class="fw-bold">${segment.sourceName || 'Unknown'}</div>
            <div class="text-muted" style="font-size: 0.75rem;">
              ${segment.startLat.toFixed(2)}°, ${segment.startLng.toFixed(2)}°
            </div>
          </div>
          <div class="text-primary mx-3">→</div>
          <div class="text-center">
            <div class="fw-bold">${segment.targetSourceName || 'Unknown'}</div>
            <div class="text-muted" style="font-size: 0.75rem;">
              ${segment.endLat.toFixed(2)}°, ${segment.endLng.toFixed(2)}°
            </div>
          </div>
        </div>
        
        <div class="row g-2 mb-3">
          <div class="col-6">
            <div class="border rounded p-2">
              <div class="text-muted" style="font-size: 0.75rem;">Framing</div>
              <div class="fw-bold" style="color: ${framingColor}">${framingLabel}</div>
            </div>
          </div>
          <div class="col-6">
            <div class="border rounded p-2">
              <div class="text-muted" style="font-size: 0.75rem;">Delay</div>
              <div class="fw-bold">${segment.delaySeconds || 0}s</div>
            </div>
          </div>
          <div class="col-12">
            <div class="border rounded p-2">
              <div class="text-muted" style="font-size: 0.75rem;">Published</div>
              <div class="fw-bold">${dateStr}</div>
            </div>
          </div>
        </div>
        
        ${segment.headline ? `
          <div class="border-start border-3 border-info ps-3 mb-3">
            <div class="text-muted" style="font-size: 0.75rem;">Headline</div>
            <div class="fw-bold">${segment.headline}</div>
          </div>
        ` : ''}
        
        <div class="d-flex justify-content-between border-top pt-2">
          <div class="text-center">
            <div class="text-muted" style="font-size: 0.7rem;">Manipulation</div>
            <div class="fw-bold ${segment.manipulationScore > 0.7 ? 'text-danger' : segment.manipulationScore > 0.3 ? 'text-warning' : 'text-success'}">
              ${(segment.manipulationScore * 100).toFixed(1)}%
            </div>
          </div>
          <div class="text-center">
            <div class="text-muted" style="font-size: 0.7rem;">Amplification</div>
            <div class="fw-bold ${segment.amplificationScore > 0.7 ? 'text-success' : segment.amplificationScore > 0.3 ? 'text-warning' : 'text-muted'}">
              ${(segment.amplificationScore * 100).toFixed(1)}%
            </div>
          </div>
          <div class="text-center">
            <div class="text-muted" style="font-size: 0.7rem;">Total Hops</div>
            <div class="fw-bold">${segment.totalHops || 0}</div>
          </div>
        </div>
      </div>
    `
  }

  // -------------------------------------------------------
  // Heatmap (Threat Thermal Layer)
  // -------------------------------------------------------

  _onHeatmapToggle() {
    if (this._journeyActive) return
    this._heatmapActive = !this._heatmapActive

    if (this._heatmapActive) {
      // Hide normal layers + packets
      this._globe.arcsData([]).pointsData([]).ringsData([])
      if (this._packetGroup) this._packetGroup.visible = false

      // Render heatmap (reload data so heatmap branch is taken)
      this._loadData().then(() => {
        // Start breathing pulse after data is loaded
        this._heatmapPulseId = setInterval(() => this._pulseHeatmap(), 2500)
      })
    } else {
      // Stop pulse
      if (this._heatmapPulseId) {
        clearInterval(this._heatmapPulseId)
        this._heatmapPulseId = null
      }

      // Clear heatmap, restore normal layers
      this._globe.heatmapsData([])
      this._hideHeatmapTooltip()
      if (this._packetGroup) this._packetGroup.visible = true
      this._loadData()
    }

    // Dispatch state for the toggle button UI
    window.dispatchEvent(new CustomEvent("veritas:heatmapState", {
      detail: { active: this._heatmapActive }
    }))
  }

  _pulseHeatmap() {
    if (!this._globe || !this._heatmapActive || !this._heatmapBaseData.length) return

    const pulsed = this._heatmapBaseData.map(p => ({
      lat:    p.lat,
      lng:    p.lng,
      weight: Math.min(1, p.weight * (0.92 + Math.random() * 0.16))
    }))

    this._globe.heatmapsData([pulsed])
  }

  _handleHeatmapHover(event, container) {
    if (!this._heatmapActive || !this._globe || !this._heatmapClusters.length) return

    const rect = container.getBoundingClientRect()
    const mx = event.clientX - rect.left
    const my = event.clientY - rect.top

    // Compare mouse position against each cluster's screen position
    let nearest = null
    let nearestDist = Infinity
    for (const cluster of this._heatmapClusters) {
      const screenPos = this._globe.getScreenCoords(cluster.lat, cluster.lng)
      if (!screenPos) continue

      const dx = screenPos.x - mx
      const dy = screenPos.y - my
      const dist = Math.sqrt(dx * dx + dy * dy)
      if (dist < nearestDist) {
        nearestDist = dist
        nearest = cluster
      }
    }

    // 80px radius — close enough to a cluster centroid to show tooltip
    if (!nearest || nearestDist > 80) {
      this._hideHeatmapTooltip()
      return
    }

    if (this._lastHoveredCluster === nearest) return
    this._lastHoveredCluster = nearest
    this._showHeatmapTooltip(nearest)
  }

  _showHeatmapTooltip(cluster) {
    if (!this._heatmapTooltipEl) {
      this._heatmapTooltipEl = document.createElement('div')
      this._heatmapTooltipEl.className = 'vt-heatmap-tooltip'
      document.querySelector('.veritas-globe-section')?.appendChild(this._heatmapTooltipEl)
    }

    const threatColor = cluster.avgThreat >= 7 ? '#ff3a5e'
      : cluster.avgThreat >= 4 ? '#ffc107'
      : cluster.avgThreat >= 1 ? '#00ff87' : '#64748b'

    const headlines = (cluster.topHeadlines || []).map(h =>
      `<div style="margin-bottom:4px;">
        <span style="color:${threatColor};font-size:8px;">■</span>
        <span style="color:#8b95a5;font-size:8px;margin-right:4px;">${h.source}</span>
        <span style="font-size:10px;">${h.headline}</span>
      </div>`
    ).join('')

    this._heatmapTooltipEl.innerHTML = `
      <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:6px;">
        <span style="color:#00f0ff;font-size:9px;letter-spacing:0.12em;">${cluster.name} [${cluster.iso}]</span>
        <span style="color:${threatColor};font-size:9px;font-weight:700;">THREAT ${cluster.avgThreat}</span>
      </div>
      <div style="display:flex;gap:14px;margin-bottom:8px;">
        <div>
          <div style="color:#8b95a5;font-size:8px;letter-spacing:0.08em;">SIGNALS</div>
          <div style="font-size:16px;font-weight:700;color:#e0e6ed;">${cluster.articleCount}</div>
        </div>
        <div>
          <div style="color:#8b95a5;font-size:8px;letter-spacing:0.08em;">AVG THREAT</div>
          <div style="font-size:16px;font-weight:700;color:${threatColor};">${cluster.avgThreat}</div>
        </div>
      </div>
      ${headlines ? `<div style="border-top:1px solid rgba(0,240,255,0.15);padding-top:6px;">${headlines}</div>` : ''}
    `

    this._heatmapTooltipEl.classList.add('is-visible')
  }

  _hideHeatmapTooltip() {
    if (this._heatmapTooltipEl) {
      this._heatmapTooltipEl.classList.remove('is-visible')
    }
    this._lastHoveredCluster = null
  }

  _flareHeatmapAt(lat, lng) {
    if (!this._heatmapActive) return

    const flare = { lat, lng, weight: 1.0 }
    this._heatmapBaseData.push(flare)
    this._globe.heatmapsData([[...this._heatmapBaseData]])

    setTimeout(() => {
      const idx = this._heatmapBaseData.indexOf(flare)
      if (idx !== -1) this._heatmapBaseData.splice(idx, 1)
    }, 2000)
  }

  _onBroadcast(data) {
    if (!this._globe) return
    if (this._journeyActive) return

    if (data.type === "new_point") {
      const current = this._globe.pointsData()
      this._globe.pointsData([...current, data.point])

      // Flare heatmap at new article location
      if (data.point.lat && data.point.lng) {
        this._flareHeatmapAt(data.point.lat, data.point.lng)
      }
    } else if (data.type === "update_point") {
      const current = this._globe.pointsData()
      this._globe.pointsData(
        current.map(p => p.id === data.point.id ? { ...p, ...data.point } : p)
      )
    }
  }

  _onModeChanged(event) {
    // Mode toggled (demo ↔ live) — re-fetch globe data
    if (this._journeyActive) return
    this._loadData()
  }

  _onIsolateToggle() {
    if (this._journeyActive) return
    this._hideIsolated = !this._hideIsolated

    if (this._globe && !this._heatmapActive) {
      // Re-apply filter to current data without re-fetching
      const allPoints = this._allPoints || []
      const allArcs   = this._allArcs || []

      if (this._hideIsolated) {
        // Build set of point IDs that participate in at least one arc
        const connectedIds = new Set()
        allArcs.forEach(arc => {
          if (arc.articleId) connectedIds.add(arc.articleId)
        })
        const filtered = allPoints.filter(p => connectedIds.has(p.id))
        this._globe.pointsData(filtered)
      } else {
        this._globe.pointsData(allPoints)
      }
    }

    window.dispatchEvent(new CustomEvent("veritas:isolateState", {
      detail: { active: this._hideIsolated }
    }))
  }

  _onViewModeChanged(event) {
    if (this._journeyActive) return
    const { mode } = event.detail
    if (mode === "all") {
      this._loadData()
    } else if (mode === "search" && this._currentSearchQuery) {
      window.dispatchEvent(new CustomEvent("veritas:search", {
        detail: { query: this._currentSearchQuery }
      }))
    }
  }

  // Handle search event from search_controller.js / search_intelligence_controller.js
  async _onSearchEvent(event) {
    if (this._journeyActive) return
    const { query } = event.detail

    if (!query) {
      this._loadData()
      return
    }

    this._currentSearchQuery = query

    // Purge the globe immediately so the user never sees stale arcs while loading
    if (this._globe) {
      this._globe.arcsData([]).pointsData([]).ringsData([])
      if (this._packetGroup) this._packetGroup.visible = false
    }

    // Cancel any in-flight request (initial load, timeline change, or previous search)
    this._abortController?.abort()
    this._abortController = new AbortController()
    const signal = this._abortController.signal

    try {
      const params = new URLSearchParams({
        search_query: query,
        view: 'segments'
      })

      if (this._currentTopic) {
        params.set("topic", this._currentTopic)
      }

      const url = `${this.dataUrlValue}?${params.toString()}`
      const response = await fetch(url, { signal })
      const data = await response.json()

      // Store heatmap base data + clusters
      this._heatmapBaseData = data.heatmap || []
      this._heatmapClusters = data.heatmapClusters || []

      // Store full datasets for isolate filter
      this._allPoints = data.points || []
      this._allArcs   = data.arcs || []

      if (this._heatmapActive) {
        this._globe.heatmapsData([this._heatmapBaseData])
      } else {
        const rings = (data.regions || []).map(r => ({
          ...r,
          ...(THREAT_RING[parseInt(r.threat, 10)] || THREAT_RING[1])
        }))

        let visiblePoints = this._allPoints
        if (this._hideIsolated) {
          const connectedIds = new Set()
          this._allArcs.forEach(arc => { if (arc.articleId) connectedIds.add(arc.articleId) })
          visiblePoints = this._allPoints.filter(p => connectedIds.has(p.id))
        }

        this._globe
          .pointsData(visiblePoints)
          .arcsData(this._allArcs)
          .ringsData(rings)

        if (this._packetGroup) this._packetGroup.visible = true
        if (this._globe) this._updatePackets()
      }

      // Fly to the centroid of the first primary arc
      const primaryArc = (data.arcs || []).find(a => a.tier === 1) || data.arcs?.[0]
      if (primaryArc) {
        const midLat = (primaryArc.startLat + primaryArc.endLat) / 2
        const midLng = (primaryArc.startLng + primaryArc.endLng) / 2
        this._flyTo(midLat, midLng, 2.0)
      }

      console.log(`[GlobeController] Search: "${query}" — ${data.arcs?.length || 0} arcs (${(data.arcs || []).filter(a => a.tier === 1).length} primary)`)
    } catch (err) {
      if (err.name === 'AbortError') return  // superseded by a newer search, ignore
      console.error('[GlobeController] Search filter failed:', err)
      this._loadData()
    }
  }

  _onSearchClearEvent() {
    if (this._journeyActive) return
    this._currentSearchQuery = null
    this._loadData()
  }

  // -------------------------------------------------------
  // Utilities
  // -------------------------------------------------------

  _cloneLayer(layer) {
    return JSON.parse(JSON.stringify(layer))
  }

  // Convert a 6-digit hex color to rgba with the given opacity (0–1).
  // Used to dim secondary arcs without losing their framing-shift color identity.
  _hexToRgba(hex, alpha) {
    const h = hex.replace('#', '')
    if (h.length !== 6) return hex
    const r = parseInt(h.slice(0, 2), 16)
    const g = parseInt(h.slice(2, 4), 16)
    const b = parseInt(h.slice(4, 6), 16)
    return `rgba(${r},${g},${b},${alpha})`
  }
}
