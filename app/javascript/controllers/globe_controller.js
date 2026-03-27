import { Controller } from "@hotwired/stimulus"
import consumer from "channels/consumer"

const THREAT_RING = {
  3: { color: "#ff3a5e", maxRadius: 2.5, propagationSpeed: 4.0, repeatPeriod: 2000 },
  2: { color: "#ffc107", maxRadius: 1.8, propagationSpeed: 3.0, repeatPeriod: 3000 },
  1: { color: "#00ff87", maxRadius: 1.2, propagationSpeed: 2.0, repeatPeriod: 4000 }
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
    // Globe mode: "global" | "network" | "search"
    this._globeMode          = "global"
    this._networkCenterArticleId = null
    this._networkData        = null
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
    this._selectedArcArticleId   = null
    this._timelapseState         = null
    this._timelapseOverlay       = null
    this._preTimelapseState      = null
    this._timelapseContext        = { mode: 'exploration', routeId: null }
    this._timelapseToggleHandler = (e) => this._onTimelapseToggle(e)
    this._backToGlobalHandler    = ()  => this._returnToGlobal()
    this._exploreArticleHandler  = (e) => this._loadNetworkView(e.detail?.articleId)
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
    window.addEventListener("veritas:timelapseToggle",   this._timelapseToggleHandler)
    window.addEventListener("veritas:backToGlobal",      this._backToGlobalHandler)
    window.addEventListener("veritas:exploreArticle",    this._exploreArticleHandler)
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
    window.removeEventListener("veritas:timelapseToggle",   this._timelapseToggleHandler)
    window.removeEventListener("veritas:backToGlobal",      this._backToGlobalHandler)
    window.removeEventListener("veritas:exploreArticle",    this._exploreArticleHandler)
    if (this._timelapseState) this._timelapseState.playing = false
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
    if (this._refreshTimeout) clearTimeout(this._refreshTimeout)
  }

  get globe() {
    return this._globe
  }

  captureJourneyState() {
    if (!this._globe) return null

    const controls = this._globe.controls()

    return {
      arcsData: this._cloneLayer(this._globe.arcsData() || []),
      hexBinPointsData: this._cloneLayer(this._globe.hexBinPointsData() || []),
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
      .hexBinPointsData(this._cloneLayer(state.hexBinPointsData || []))
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
      // Hex-bin layer — aggregates signals into hexagonal bins
      // Height = signal density, Color = max threat level in bin
      .hexBinPointsData([])
      .hexBinPointLat(d => d.lat)
      .hexBinPointLng(d => d.lng)
      .hexBinPointWeight(d => this._hexBinWeight(d))
      .hexBinResolution(3)
      .hexBinMerge(true)
      .hexMargin(0.3)
      .hexTopColor(d => this._hexColor(d, 'top'))
      .hexSideColor(d => this._hexColor(d, 'side'))
      .hexAltitude(d => Math.min(0.15, 0.005 + (d.sumWeight * 0.003)))
      .hexTransitionDuration(800)
      .onHexHover(hex => this._onHexHover(hex))
      .onHexClick(hex => this._onHexClicked(hex))
      // Arcs layer (narrative arcs)
      // tier 1 (top 5 by strength): thick, animated dash, full opacity
      // tier 2 (next 10): thin, solid, 35% opacity
      // no tier (legacy fallback arcs): use thickness field
      .arcColor(d => this._arcColorWithDrift(d))
      .arcDashLength(d => {
        if (d.arcDashLength != null) return d.arcDashLength
        // Network arcs: style by dominant connection type
        if (d.connectionTypes) {
          const dom = this._dominantConnectionType(d)
          if (dom === 'narrative_route') return 0.4   // animated dash — shows flow direction
          if (dom === 'embedding_similarity') return 0.2  // short static dashes
          return 0  // gdelt_event + shared_entities = solid line
        }
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
        // Network arcs: style by dominant connection type
        if (d.connectionTypes) {
          const dom = this._dominantConnectionType(d)
          if (dom === 'narrative_route') return 0.15   // gap for animated pulse
          if (dom === 'embedding_similarity') return 0.15  // even dash pattern
          return 0  // solid for gdelt + entities
        }
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
      .arcDashAnimateTime(d => {
        if (d.arcDashAnimateTime != null) return d.arcDashAnimateTime
        // Network arcs: only narrative_route gets animation (shows propagation direction)
        if (d.connectionTypes) {
          const dom = this._dominantConnectionType(d)
          if (dom === 'narrative_route') {
            const strength = d.strength || 0.5
            return Math.round(3000 - (strength * 1500))  // stronger = faster flow
          }
          return 0  // all other types: static (no animation)
        }
        if (d.driftIntensity != null) {
          const intensity = d.driftIntensity
          return Math.round(4000 - (intensity * 2800))
        }
        return d.tier === 1 ? 2500 : 0
      })
      .arcStroke(d => {
        // Highlight selected arc with thicker stroke
        if (this._selectedArcArticleId && String(d.articleId) === String(this._selectedArcArticleId)) {
          return 2.5
        }
        // Network arcs: stroke by dominant connection type
        if (d.connectionTypes) {
          const dom = this._dominantConnectionType(d)
          const base = d.thickness || 0.5
          if (dom === 'narrative_route') return Math.max(base, 1.0)  // thick — strongest signal
          if (dom === 'gdelt_event') return Math.max(base, 0.7)     // solid and visible
          if (dom === 'embedding_similarity') return Math.min(base, 0.5)  // thinner — algorithmic
          if (dom === 'shared_entities') return Math.min(base, 0.3)  // very thin — weakest hint
          return base
        }
        if (d.arcStroke != null) return d.arcStroke
        // Visibility-weighted thickness: high confidence + high threat = thicker
        if (d.visibilityWeight != null) {
          const vis = d.visibilityWeight || 0.3
          const base = d.tier === 1 ? 1.0 : (d.tier === 2 ? 0.4 : 0.3)
          return base + (vis * 1.0)  // 0.3–1.3 range on top of base
        }
        if (d.tier === 1) return 1.2
        if (d.tier === 2) return 0.5
        return d.thickness ? Math.min(d.thickness, 1.0) : 0.4
      })
      .onArcHover(arc => this._onArcHover(arc))
      .onArcClick(arc => this._onArcClicked(arc))
      // Tooltips
      .hexLabel(d => this._buildHexTooltip(d))
      .arcLabel(d => this._buildArcTooltip(d))
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
        // Subtle sonar ping — fades quickly, low max opacity
        return `rgba(${r},${g},${b},${Math.max(0, (1 - t) * 0.3)})`
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
    // If in network mode, reload network; otherwise load global network view
    if (this._globeMode === "network" && this._networkCenterArticleId) {
      return this._loadNetworkView(this._networkCenterArticleId)
    }
    return this._loadGlobalNetworkView()
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

      // Store heatmap base data + cluster summaries for thermal layer
      this._heatmapBaseData  = data.heatmap || []
      this._heatmapClusters  = data.heatmapClusters || []

      // Store full datasets for isolate filter — filter invalid coords client-side
      this._allPoints = (data.points || []).filter(p => this._isValidPoint(p))
      this._allArcs   = (data.arcs || []).filter(a => this._isValidArc(a))
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
          .hexBinPointsData(visiblePoints)
          .arcsData(this._allArcs)
          .ringsData([])  // No rings on initial load — hex bins are enough

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
        .hexBinPointsData([...this._allPoints])
        .arcsData([...this._allArcs || []])
    }
  }

  _pointColorForPerspective(d) {
    if (d?._journey) return d.color || '#00f0ff'
    const c = d.color || '#00f0ff'
    if (this._currentPerspective === 'all') return c
    if (d.perspectiveSlug === this._currentPerspective) return c
    // Unclassified sources stay moderately visible as neutral context;
    // articles from a different known perspective fade to near-invisible.
    return this._hexToRgba(c, d.perspectiveSlug === 'unclassified' ? 0.28 : 0.10)
  }

  _arcColorForPerspective(d) {
    if (d?._journey) return d.color || '#00f0ff'

    // Highlight selected arc: bright glowing version of its own color
    if (this._selectedArcArticleId && String(d.articleId) === String(this._selectedArcArticleId)) {
      const raw = Array.isArray(d.color) ? d.color[0] : (d.color || '#00f0ff')
      const p = this._parseColor(raw)
      return `rgba(${Math.min(255, p.r + Math.round((255 - p.r) * 0.5))},${Math.min(255, p.g + Math.round((255 - p.g) * 0.5))},${Math.min(255, p.b + Math.round((255 - p.b) * 0.5))},1)`
    }

    const c = Array.isArray(d.color) ? d.color[0] : (d.color || '#00f0ff')
    const baseTierAlpha = d.tier === 2 ? 0.35 : 1.0

    // Dim non-selected arcs when one is selected
    if (this._selectedArcArticleId) {
      return this._hexToRgba(c, 0.12)
    }

    if (this._currentPerspective === 'all') {
      return d.tier === 2 ? this._hexToRgba(c, 0.35) : c
    }
    const isActive = d.perspectiveSlug === this._currentPerspective
    if (isActive) return this._hexToRgba(c, baseTierAlpha)
    return this._hexToRgba(c, d.perspectiveSlug === 'unclassified' ? 0.18 : 0.05)
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
    // Enter Network View — explore this article's narrative network
    if (point.id) this._loadNetworkView(point.id)
  }

  _onPointHover(point) {
    this._pointHovered = Boolean(point)
    this._syncAutoRotate()
  }

  _onArcClicked(arc) {
    if (!arc) return
    if (this._journeyActive) return

    const midLat = (arc.startLat + arc.endLat) / 2
    const midLng = (arc.startLng + arc.endLng) / 2
    this._flyTo(midLat, midLng, 2.0)

    // Network arcs: re-center on the other end of the connection
    if (arc.connectionTypes) {
      const targetId = arc.targetArticleId || arc.sourceArticleId
      if (targetId && targetId !== this._networkCenterArticleId) {
        this._loadNetworkView(targetId)
        return
      }
    }

    if (arc.articleId) this._setActiveCard(arc.articleId)

    // Show Bloom/Chronicle menu for any arc with a route
    if (arc.routeId) {
      this._showRouteChoiceMenu(arc)
    }

    // Show hop details in timeline sidebar
    this._showHopDetails(arc)

    // Highlight this arc visually
    this._selectedArcArticleId = arc.articleId
    this._globe.arcsData(this._globe.arcsData())

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
    if (articleId) this._highlightArcForArticle(articleId)
  }

  _onJourneyActivated(event) {
    if (!this._globe) return

    // If timelapse is active, cleanly exit it first so captureJourneyState
    // captures the real globe state (not the timelapse-modified one).
    if (this._timelapseState) {
      const state = this._timelapseState
      if (state) state.playing = false
      this._timelapseState = null

      // Immediately restore original callbacks + data (synchronous, no fade)
      this._restoreTimelapseState()
      if (this._timelapseOverlay) {
        this._timelapseOverlay.remove()
        this._timelapseOverlay = null
      }
      window.dispatchEvent(new CustomEvent("veritas:timelapseState", {
        detail: { active: false }
      }))
    }

    this._journeyActive = true
    this._preJourneyState = event.detail?.state || this._preJourneyState || this.captureJourneyState()
    this._hideRouteChoiceMenu()

    if (this._packetGroup) this._packetGroup.visible = false
    this._globe.arcsData([]).hexBinPointsData([]).ringsData([])
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
      <button class="vt-route-choice-btn vt-route-choice-btn--story" type="button">⏱ STORY</button>
    `

    const [bloomButton, chronicleButton, storyButton] = menu.querySelectorAll("button")
    bloomButton?.addEventListener("click", (clickEvent) => {
      clickEvent.stopPropagation()
      this._startJourneyFromRoute(route, "bloom")
    })
    chronicleButton?.addEventListener("click", (clickEvent) => {
      clickEvent.stopPropagation()
      this._startJourneyFromRoute(route, "chronicle")
    })
    storyButton?.addEventListener("click", (clickEvent) => {
      clickEvent.stopPropagation()
      this._hideRouteChoiceMenu()
      this.startStoryTimelapse(route.routeId || route.id)
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
    this._clearArcSelection()
  }

  _clearArcSelection() {
    if (!this._selectedArcArticleId) return
    this._selectedArcArticleId = null
    if (this._globe) this._globe.arcsData(this._globe.arcsData()) // re-render with normal colors
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

  _highlightArcForArticle(articleId) {
    if (!this._globe) return

    // Find the arc matching this article
    const arcs = this._globe.arcsData() || []
    const arc = arcs.find(a => String(a.articleId) === String(articleId))
    if (!arc) return

    // Set the selected arc so the color callback can brighten it
    this._selectedArcArticleId = articleId
    this._globe.arcsData(arcs) // trigger re-render

    // Fly to the arc midpoint
    const midLat = (arc.startLat + arc.endLat) / 2
    const midLng = (arc.startLng + arc.endLng) / 2
    this._flyTo(midLat, midLng, 2.0)

    // Show Bloom/Chronicle menu if the arc has a route
    if (arc.routeId) {
      this._showRouteChoiceMenu(arc)
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

        ${segment.framingExplanation ? `
          <div class="border-start border-3 ps-3 mb-3" style="border-color: ${framingColor} !important;">
            <div class="text-muted" style="font-size: 0.75rem;">Why ${framingLabel}</div>
            <div style="font-size: 0.85rem; color: #cbd5e1;">${segment.framingExplanation}</div>
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
      this._globe.arcsData([]).hexBinPointsData([]).ringsData([])
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
      const current = this._globe.hexBinPointsData() || []
      this._globe.hexBinPointsData([...current, data.point])

      // Fire a one-shot ring at the new signal location
      if (data.point.lat && data.point.lng) {
        this._onNewSignal(data.point)
        this._flareHeatmapAt(data.point.lat, data.point.lng)
      }
    } else if (data.type === "update_point") {
      const current = this._globe.hexBinPointsData() || []
      this._globe.hexBinPointsData(
        current.map(p => p.id === data.point.id ? { ...p, ...data.point } : p)
      )
    } else if (data.type === "routes_updated" || data.type === "articles_fetched") {
      // New arcs or articles are in the DB — debounce a globe data refresh so
      // multiple rapid broadcasts coalesce into a single re-fetch.
      if (this._refreshTimeout) clearTimeout(this._refreshTimeout)
      this._refreshTimeout = setTimeout(() => this._loadData(), 2000)
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
        this._globe.hexBinPointsData(filtered)
      } else {
        this._globe.hexBinPointsData(allPoints)
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
    this._globeMode = "search"

    // Purge the globe immediately so the user never sees stale arcs while loading
    if (this._globe) {
      this._globe.arcsData([]).hexBinPointsData([]).ringsData([])
      if (this._packetGroup) this._packetGroup.visible = false
    }

    // Cancel any in-flight request (initial load, timeline change, or previous search)
    this._abortController?.abort()
    this._abortController = new AbortController()
    const signal = this._abortController.signal

    try {
      // 1. Fetch legacy globe_data (points + heatmap + legacy arcs)
      const params = new URLSearchParams({
        search_query: query,
        view: 'segments'
      })

      if (this._currentTopic) {
        params.set("topic", this._currentTopic)
      }

      const globeUrl = `${this.dataUrlValue}?${params.toString()}`

      // 2. Fetch network arcs from ArticleNetworkService (4-type connections)
      const networkUrl = `/api/article_network/search?search_query=${encodeURIComponent(query)}`

      // Parallel fetch — both requests at once
      const [globeResponse, networkResponse] = await Promise.all([
        fetch(globeUrl, { signal }),
        fetch(networkUrl, { signal }).catch(() => null)
      ])

      const data = await globeResponse.json()
      let networkData = null
      if (networkResponse?.ok) {
        networkData = await networkResponse.json()
      }

      // Store heatmap base data + clusters
      this._heatmapBaseData = data.heatmap || []
      this._heatmapClusters = data.heatmapClusters || []

      // Store points from globe_data
      this._allPoints = (data.points || []).filter(p => this._isValidPoint(p))

      // Merge arcs: network arcs (primary, 4-type) + legacy arcs (secondary, fallback)
      const legacyArcs = (data.arcs || []).filter(a => this._isValidArc(a))
      const networkArcs = (networkData?.arcs || []).filter(a => this._isValidArc(a))
      this._allArcs = networkArcs.length > 0
        ? this._mergeArcSets(networkArcs, legacyArcs)
        : legacyArcs

      if (this._heatmapActive) {
        this._globe.heatmapsData([this._heatmapBaseData])
      } else {
        let visiblePoints = this._allPoints
        if (this._hideIsolated) {
          const connectedIds = new Set()
          this._allArcs.forEach(arc => {
            if (arc.articleId) connectedIds.add(arc.articleId)
            if (arc.sourceArticleId) connectedIds.add(arc.sourceArticleId)
            if (arc.targetArticleId) connectedIds.add(arc.targetArticleId)
          })
          visiblePoints = this._allPoints.filter(p => connectedIds.has(p.id))
        }

        this._globe
          .hexBinPointsData(visiblePoints)
          .arcsData(this._allArcs)
          .ringsData([])

        if (this._packetGroup) this._packetGroup.visible = true
        if (this._globe) this._updatePackets()
      }

      // Fly to the centroid of the first arc
      const primaryArc = this._allArcs.find(a => a.connectionTypes) || this._allArcs.find(a => a.tier === 1) || this._allArcs[0]
      if (primaryArc) {
        const midLat = (primaryArc.startLat + primaryArc.endLat) / 2
        const midLng = (primaryArc.startLng + primaryArc.endLng) / 2
        this._flyTo(midLat, midLng, 2.0)
      }

      console.log(`[VERITAS Globe] Search: "${query}" — ${networkArcs.length} network + ${legacyArcs.length} legacy = ${this._allArcs.length} arcs`)
    } catch (err) {
      if (err.name === 'AbortError') return
      console.error('[VERITAS Globe] Search filter failed:', err)
      this._loadData()
    }
  }

  _onSearchClearEvent() {
    if (this._journeyActive) return
    this._currentSearchQuery = null
    this._returnToGlobal()
  }

  // -------------------------------------------------------
  // Globe Mode: Network View
  // -------------------------------------------------------

  async _loadNetworkView(articleId) {
    if (!articleId) return
    this._globeMode = "network"
    this._networkCenterArticleId = articleId

    // Abort any in-flight request
    this._abortController?.abort()
    this._abortController = new AbortController()
    const signal = this._abortController.signal

    // Clear globe while loading
    if (this._globe) {
      this._globe.arcsData([]).ringsData([])
      if (this._packetGroup) this._packetGroup.visible = false
    }

    try {
      const url = `/api/article_network/${articleId}?depth=2&time_window=48`
      const response = await fetch(url, { signal })
      const data = await response.json()

      this._networkData = data
      this._renderNetworkData(data, articleId)

      // Dispatch event for sidebar
      window.dispatchEvent(new CustomEvent("veritas:networkLoaded", {
        detail: { articleId, data, mode: "network" }
      }))

      // Show back-to-global button
      this._showBackToGlobalButton(true)

      console.log(`[VERITAS Globe] Network View: Article #${articleId} — ${data.arcs?.length || 0} connections, ${data.articles?.length || 0} nodes`)
    } catch (err) {
      if (err.name === 'AbortError') return
      console.error('[VERITAS Globe] Network view failed:', err)
      this._returnToGlobal()
    }
  }

  // -------------------------------------------------------
  // Globe Mode: Global Network View
  // -------------------------------------------------------

  async _loadGlobalNetworkView() {
    this._globeMode = "global"
    this._networkCenterArticleId = null

    this._abortController?.abort()
    this._abortController = new AbortController()
    const signal = this._abortController.signal

    try {
      // Fetch global network (top threat articles + connections)
      const networkUrl = `/api/article_network/global`
      const response = await fetch(networkUrl, { signal })
      const networkData = await response.json()

      // Also fetch the standard globe data for points/heatmap
      const params = new URLSearchParams({ view: "segments" })
      if (this._currentTopic) params.set("topic", this._currentTopic)
      if (this._currentTimestamp) params.set("to", this._currentTimestamp)
      const globeUrl = `${this.dataUrlValue}?${params.toString()}`
      const globeResponse = await fetch(globeUrl, { signal })
      const globeData = await globeResponse.json()

      // Store heatmap data from standard response
      this._heatmapBaseData = globeData.heatmap || []
      this._heatmapClusters = globeData.heatmapClusters || []
      this._allPoints = (globeData.points || []).filter(p => this._isValidPoint(p))

      // Merge: use standard points + network arcs (overlaid on existing segment arcs)
      const existingArcs = (globeData.arcs || []).filter(a => this._isValidArc(a))
      const networkArcs = (networkData.arcs || []).filter(a => this._isValidArc(a))

      // Combine — network arcs first (higher priority), then existing segments
      // Deduplicate by start/end proximity
      const combinedArcs = this._mergeArcSets(networkArcs, existingArcs)

      this._allArcs = combinedArcs
      this._allRoutes = globeData.routes || []

      if (this._heatmapActive) {
        this._globe.heatmapsData([this._heatmapBaseData])
      } else {
        let visiblePoints = this._allPoints
        if (this._hideIsolated) {
          const connectedIds = new Set()
          combinedArcs.forEach(arc => {
            if (arc.articleId) connectedIds.add(arc.articleId)
            if (arc.sourceArticleId) connectedIds.add(arc.sourceArticleId)
            if (arc.targetArticleId) connectedIds.add(arc.targetArticleId)
          })
          visiblePoints = this._allPoints.filter(p => connectedIds.has(p.id))
        }

        this._globe
          .hexBinPointsData(visiblePoints)
          .arcsData(combinedArcs)
          .ringsData([])

        if (this._packetGroup) this._packetGroup.visible = true
        this._updatePackets()
      }

      this._showBackToGlobalButton(false)

      console.log(`[VERITAS Globe] Global Network View — ${networkArcs.length} network arcs + ${existingArcs.length} segment arcs`)
    } catch (err) {
      if (err.name === 'AbortError') return
      console.error('[VERITAS Globe] Global network view failed, falling back:', err)
      // Fallback to original data load
      this._fetchAndRender()
    }
  }

  // -------------------------------------------------------
  // Globe Mode: Return to Global
  // -------------------------------------------------------

  _returnToGlobal() {
    this._globeMode = "global"
    this._networkCenterArticleId = null
    this._networkData = null
    this._showBackToGlobalButton(false)

    window.dispatchEvent(new CustomEvent("veritas:networkCleared"))

    this._loadGlobalNetworkView()
  }

  // -------------------------------------------------------
  // Network Data Renderer
  // -------------------------------------------------------

  _renderNetworkData(data, centerArticleId) {
    if (!this._globe || !data) return

    const articles = data.articles || []
    const arcs = (data.arcs || []).filter(a => this._isValidArc(a))

    // Render limit
    const renderArcs = arcs.slice(0, 60)

    // Build points from network articles
    const points = articles.filter(a => this._isValidPoint(a)).map(a => ({
      id: a.id,
      lat: a.lat,
      lng: a.lng,
      name: a.headline || a.source,
      headline: a.headline,
      source: a.source,
      country: a.country,
      color: a.isCenter ? '#00ffcc' : (a.sentimentColor || '#6b7280'),
      size: a.isCenter ? 0.8 : 0.4,
      threatLevel: a.threatLevel,
      sentimentLabel: a.sentimentLabel,
      isCenter: a.isCenter,
      perspectiveSlug: a.perspectiveSlug
    }))

    // Fly to center article
    const center = articles.find(a => a.isCenter)
    if (center) {
      this._flyTo(center.lat, center.lng, 2.2)
    }

    // Rings on the center article
    const rings = center ? [{ lat: center.lat, lng: center.lng, maxR: 3, propagationSpeed: 2, repeatPeriod: 1500 }] : []

    this._allPoints = points
    this._allArcs = renderArcs

    this._globe
      .hexBinPointsData(points)
      .arcsData(renderArcs)
      .ringsData(rings)

    if (this._packetGroup) this._packetGroup.visible = true
    this._updatePackets()
  }

  // -------------------------------------------------------
  // Arc Set Merger (deduplicates by geo proximity)
  // -------------------------------------------------------

  _mergeArcSets(primary, secondary) {
    const merged = [...primary]
    const existing = new Set()

    primary.forEach(arc => {
      existing.add(`${Math.round(arc.startLat * 10)},${Math.round(arc.startLng * 10)}-${Math.round(arc.endLat * 10)},${Math.round(arc.endLng * 10)}`)
    })

    secondary.forEach(arc => {
      const key = `${Math.round(arc.startLat * 10)},${Math.round(arc.startLng * 10)}-${Math.round(arc.endLat * 10)},${Math.round(arc.endLng * 10)}`
      const keyReverse = `${Math.round(arc.endLat * 10)},${Math.round(arc.endLng * 10)}-${Math.round(arc.startLat * 10)},${Math.round(arc.startLng * 10)}`
      if (!existing.has(key) && !existing.has(keyReverse)) {
        merged.push(arc)
        existing.add(key)
      }
    })

    return merged
  }

  // -------------------------------------------------------
  // Back to Global UI
  // -------------------------------------------------------

  _showBackToGlobalButton(show) {
    let btn = document.getElementById('veritas-back-to-global')
    if (show && !btn) {
      btn = document.createElement('button')
      btn.id = 'veritas-back-to-global'
      btn.innerHTML = '&larr; GLOBAL VIEW'
      btn.style.cssText = `
        position:fixed;top:80px;left:50%;transform:translateX(-50%);z-index:9999;
        background:rgba(0,20,30,0.85);backdrop-filter:blur(8px);
        border:1px solid rgba(0,255,204,0.3);border-radius:6px;
        padding:8px 20px;color:#00ffcc;font-family:'JetBrains Mono',monospace;
        font-size:11px;letter-spacing:2px;text-transform:uppercase;cursor:pointer;
        transition:all 0.3s ease;box-shadow:0 4px 20px rgba(0,0,0,0.4);
      `
      btn.addEventListener('mouseenter', () => { btn.style.borderColor = '#00ffcc'; btn.style.boxShadow = '0 0 20px rgba(0,255,204,0.3)' })
      btn.addEventListener('mouseleave', () => { btn.style.borderColor = 'rgba(0,255,204,0.3)'; btn.style.boxShadow = '0 4px 20px rgba(0,0,0,0.4)' })
      btn.addEventListener('click', () => this._returnToGlobal())
      document.body.appendChild(btn)
    } else if (!show && btn) {
      btn.remove()
    }
  }

  // -------------------------------------------------------
  // Utilities
  // -------------------------------------------------------

  _cloneLayer(layer) {
    return JSON.parse(JSON.stringify(layer))
  }

  // -------------------------------------------------------
  // Hex-bin layer helpers
  // -------------------------------------------------------

  _hexBinWeight(d) {
    const threat = (d.threat_level || '').toUpperCase()
    if (threat === 'SEVERE' || threat === 'CRITICAL') return 3
    if (threat === 'HIGH') return 2
    if (threat === 'MODERATE') return 1.5
    return 1
  }

  _hexColor(bin, face) {
    const points = bin.points || []
    let maxThreat = 0
    points.forEach(p => {
      const threat = (p.threat_level || '').toUpperCase()
      if (threat === 'SEVERE' || threat === 'CRITICAL') maxThreat = Math.max(maxThreat, 3)
      else if (threat === 'HIGH') maxThreat = Math.max(maxThreat, 2)
      else if (threat === 'MODERATE') maxThreat = Math.max(maxThreat, 1)
    })

    const alpha = face === 'top' ? 0.9 : 0.7
    if (maxThreat >= 3) return `rgba(255, 40, 40, ${alpha})`      // Red — SEVERE
    if (maxThreat >= 2) return `rgba(255, 140, 0, ${alpha})`      // Orange — HIGH
    if (maxThreat >= 1) return `rgba(255, 210, 0, ${alpha})`      // Yellow — MODERATE
    return `rgba(0, 255, 204, ${alpha})`                           // Teal — normal
  }

  _buildHexTooltip(bin) {
    if (!bin) return ''
    const points = bin.points || []
    const count = points.length
    if (count === 0) return ''

    // Determine max threat in the bin
    let maxThreat = 0
    let maxThreatLabel = 'NORMAL'
    points.forEach(p => {
      const threat = (p.threat_level || '').toUpperCase()
      if ((threat === 'SEVERE' || threat === 'CRITICAL') && maxThreat < 3) { maxThreat = 3; maxThreatLabel = threat }
      else if (threat === 'HIGH' && maxThreat < 2) { maxThreat = 2; maxThreatLabel = 'HIGH' }
      else if (threat === 'MODERATE' && maxThreat < 1) { maxThreat = 1; maxThreatLabel = 'MODERATE' }
    })
    const threatColor = maxThreat >= 3 ? '#ff2828' : maxThreat >= 2 ? '#ff8c00' : maxThreat >= 1 ? '#ffd200' : '#00ffcc'

    // Show up to 3 headlines from the bin
    const headlines = points.slice(0, 3).map(p =>
      `<div style="margin-bottom:3px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;max-width:280px;">
        <span style="color:${threatColor};font-size:8px;">&#9632;</span>
        <span style="color:#8b95a5;font-size:8px;margin-right:4px;">${p.source || 'UNKNOWN'}</span>
        <span style="font-size:10px;">${p.headline || 'No headline'}</span>
      </div>`
    ).join('')

    return `
      <div style="
        background:rgba(10,12,20,0.92);
        border:1px solid rgba(0,240,255,0.3);
        border-radius:4px;
        padding:8px 12px;
        font-family:'JetBrains Mono',monospace;
        font-size:11px;
        color:#e0e6ed;
        max-width:320px;
        line-height:1.4;
        box-shadow:0 0 20px rgba(0,240,255,0.15);
      ">
        <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:6px;">
          <span style="color:#00f0ff;font-size:9px;letter-spacing:0.12em;">SIGNAL CLUSTER</span>
          <span style="color:${threatColor};font-size:9px;font-weight:700;">${maxThreatLabel}</span>
        </div>
        <div style="display:flex;gap:14px;margin-bottom:8px;">
          <div>
            <div style="color:#8b95a5;font-size:8px;letter-spacing:0.08em;">SIGNALS</div>
            <div style="font-size:16px;font-weight:700;color:#e0e6ed;">${count}</div>
          </div>
          <div>
            <div style="color:#8b95a5;font-size:8px;letter-spacing:0.08em;">MAX THREAT</div>
            <div style="font-size:16px;font-weight:700;color:${threatColor};">${maxThreatLabel}</div>
          </div>
        </div>
        ${headlines ? `<div style="border-top:1px solid rgba(0,240,255,0.15);padding-top:6px;">${headlines}</div>` : ''}
      </div>
    `
  }

  _onHexHover(hex) {
    this._pointHovered = Boolean(hex)
    this._syncAutoRotate()
  }

  _onHexClicked(hex) {
    if (!hex || !this._globe) return
    if (this._journeyActive) return
    // Fly to the hex centroid
    const center = hex.center || {}
    if (center.lat != null && center.lng != null) {
      this._flyTo(center.lat, center.lng, 2.0)
    }
  }

  _onNewSignal(point) {
    if (!this._globe) return
    const ring = {
      lat: point.lat,
      lng: point.lng,
      maxRadius: 3,
      propagationSpeed: 2,
      repeatPeriod: 0,
      color: '#00f0ff',
      threat: 1
    }
    const currentRings = this._globe.ringsData() || []
    this._globe.ringsData([...currentRings, ring])
    setTimeout(() => {
      const updated = (this._globe.ringsData() || []).filter(r => r !== ring)
      this._globe.ringsData(updated)
    }, 2000)
  }

  // Convert a 6-digit hex color to rgba with the given opacity (0–1).
  // Used to dim secondary arcs without losing their framing-shift color identity.
  // --- Drift visualization helpers ---

  _getDriftTargetColor(framing, intensity) {
    const alpha = 0.5 + (intensity * 0.3) // 0.5–0.8 range for smoother blending
    switch (framing) {
      case 'distorted':
        // Warm crimson → deep red
        return { r: Math.round(255), g: Math.round(60 - intensity * 30), b: Math.round(60 - intensity * 30), a: alpha }
      case 'amplified':
        // Amber → hot orange-magenta
        return { r: 255, g: Math.round(160 - intensity * 100), b: Math.round(40 + intensity * 60), a: alpha }
      case 'neutralized':
        // Soft steel blue
        return { r: Math.round(80 + intensity * 40), g: Math.round(160 + intensity * 40), b: Math.round(220), a: alpha }
      case 'original':
      default:
        // Clean teal/cyan
        return { r: 0, g: 200, b: 255, a: 0.4 + intensity * 0.2 }
    }
  }

  _getFramingColor(framing) {
    switch (framing) {
      case 'distorted':   return '#ff2d2d'
      case 'amplified':   return '#ff8c00'
      case 'neutralized': return '#6ea8d7'
      case 'original':    return '#00ffcc'
      default:            return '#607080'
    }
  }

  _parseColor(colorStr) {
    if (typeof colorStr === 'object' && colorStr.r !== undefined) return colorStr
    const rgbaMatch = colorStr.match(/rgba?\((\d+),\s*(\d+),\s*(\d+),?\s*([\d.]*)\)/)
    if (rgbaMatch) {
      return { r: parseInt(rgbaMatch[1]), g: parseInt(rgbaMatch[2]), b: parseInt(rgbaMatch[3]), a: rgbaMatch[4] ? parseFloat(rgbaMatch[4]) : 1.0 }
    }
    const hex = colorStr.replace('#', '')
    if (hex.length === 6) {
      return { r: parseInt(hex.slice(0, 2), 16), g: parseInt(hex.slice(2, 4), 16), b: parseInt(hex.slice(4, 6), 16), a: 1.0 }
    }
    return { r: 0, g: 255, b: 204, a: 0.6 }
  }

  _interpolateColor(c1, c2, t) {
    const r = Math.round(c1.r + (c2.r - c1.r) * t)
    const g = Math.round(c1.g + (c2.g - c1.g) * t)
    const b = Math.round(c1.b + (c2.b - c1.b) * t)
    const a = (c1.a + (c2.a - c1.a) * t).toFixed(2)
    return `rgba(${r},${g},${b},${a})`
  }

  _buildGradientStops(sourceColor, targetColor, alpha) {
    const src = this._parseColor(sourceColor)
    const tgt = typeof targetColor === 'object' ? targetColor : this._parseColor(targetColor)
    // Apply alpha override if provided (for dimming)
    if (alpha != null) { src.a = alpha; tgt.a = alpha }
    const stops = 8
    const colors = []
    for (let i = 0; i < stops; i++) {
      const t = i / (stops - 1)
      const eased = t * t // ease-in: subtle start, dramatic end
      colors.push(this._interpolateColor(src, tgt, eased))
    }
    return colors
  }

  _arcColorWithDrift(d) {
    if (d?._journey) return d.color || '#00f0ff'

    // Highlight selected arc: bright glowing version of its own color, not white
    if (this._selectedArcArticleId && String(d.articleId) === String(this._selectedArcArticleId)) {
      const c = Array.isArray(d.color) ? d.color[0] : (d.color || '#00f0ff')
      const parsed = this._parseColor(c)
      const bright = {
        r: Math.min(255, parsed.r + Math.round((255 - parsed.r) * 0.5)),
        g: Math.min(255, parsed.g + Math.round((255 - parsed.g) * 0.5)),
        b: Math.min(255, parsed.b + Math.round((255 - parsed.b) * 0.5)),
        a: 1.0
      }
      return `rgba(${bright.r},${bright.g},${bright.b},1)`
    }

    // Network arcs: color from veritasThreatScore (ALWAYS, never goldstein_scale)
    if (d.connectionTypes) {
      const threat = d.veritasThreatScore || 0
      const opacity = d.opacity || 0.7
      const sourceColor = '#4a6070'

      let threatColor
      if (threat >= 7) threatColor = '#ff4444'
      else if (threat >= 5) threatColor = '#ff8c00'
      else if (threat >= 3) threatColor = '#ffd700'
      else threatColor = '#6088a0'

      // Depth 2 arcs are dimmer
      const alpha = d.depth >= 2 ? opacity * 0.5 : opacity

      if (this._currentPerspective !== 'all') {
        const isActive = d.perspectiveSlug === this._currentPerspective
        if (!isActive) return this._buildGradientStops(sourceColor, threatColor, 0.06)
      }

      return this._buildGradientStops(sourceColor, threatColor, alpha)
    }

    // Segments with drift data: threat-aware color system
    if (d.driftIntensity != null && d.sourceName !== undefined) {
      const threat = d.veritasThreatScore || 0
      const vis = d.visibilityWeight || 0.3

      // Threat-based color: RED (conflict) → ORANGE (threat) → AMBER (warning) → STEEL (neutral)
      let threatColor
      if (d.gdeltQuadClass === 4) {
        threatColor = '#ff2020'       // Material Conflict: aggressive red
      } else if (d.gdeltQuadClass === 3 || threat >= 7) {
        threatColor = '#ff4444'       // Verbal Conflict or high threat
      } else if (threat >= 5) {
        threatColor = '#ff8c00'       // Significant threat: orange
      } else if (threat >= 3) {
        threatColor = '#ffd700'       // Moderate: amber
      } else {
        threatColor = '#6088a0'       // Low: neutral steel
      }

      const sourceColor = '#4a6070'

      // visibilityWeight modulates opacity — low-confidence or low-drift arcs fade
      const baseAlpha = vis * 0.85  // 0.26 (min) to 0.85 (max)

      // Apply perspective / selection dimming ON TOP of visibility
      if (this._selectedArcArticleId) {
        return this._buildGradientStops(sourceColor, threatColor, 0.12)
      }
      if (this._currentPerspective !== 'all') {
        const isActive = d.perspectiveSlug === this._currentPerspective
        if (!isActive) {
          const dimAlpha = d.perspectiveSlug === 'unclassified' ? 0.15 : 0.04
          return this._buildGradientStops(sourceColor, threatColor, dimAlpha)
        }
      }
      if (d.tier === 2) {
        return this._buildGradientStops(sourceColor, threatColor, baseAlpha * 0.5)
      }
      return this._buildGradientStops(sourceColor, threatColor, baseAlpha)
    }

    // Fallback: existing perspective-based color logic for non-segment arcs
    return this._arcColorForPerspective(d)
  }

  _buildArcTooltip(d) {
    if (!d) return ''

    // Network arc tooltip (from ArticleNetworkService)
    if (d.connectionTypes) {
      return this._buildNetworkArcTooltip(d)
    }

    // Drift-enhanced tooltip for segments with drift data
    if (d.driftIntensity != null && d.sourceName !== undefined) {
      const intensity = d.driftIntensity || 0
      const framing = d.framingShift || 'unknown'
      const framingColor = this._getFramingColor(framing)
      const sentimentShift = d.sentimentShift || 'N/A'
      const similarity = d.semanticSimilarity || 0
      const explanation = d.framingExplanation || ''
      const gdeltActorSummary     = d.gdeltActorSummary     || null
      const gdeltEventDescription = d.gdeltEventDescription || null
      const gdeltGoldsteinScale   = d.gdeltGoldsteinScale   != null ? d.gdeltGoldsteinScale : null
      const gdeltQuadClassLabel   = d.gdeltQuadClassLabel   || null
      const threat = d.veritasThreatScore || 0

      const driftLevel = threat >= 7 ? 'CRITICAL' :
                         threat >= 5 ? 'SIGNIFICANT' :
                         threat >= 3 ? 'MODERATE' : 'MINIMAL'
      const driftLevelColor = threat >= 7 ? '#ff2d2d' :
                              threat >= 5 ? '#ff8c00' :
                              threat >= 3 ? '#ffd700' : '#6088a0'

      const headlines = (d.sourceHeadline && d.targetHeadline) ? `
        <div style="font-size:10px;margin-bottom:8px;padding-bottom:8px;border-bottom:1px solid rgba(255,255,255,0.06);">
          <div style="color:#00ffcc;margin-bottom:3px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;max-width:380px;">▸ ${d.sourceHeadline}</div>
          <div style="color:${framingColor};white-space:nowrap;overflow:hidden;text-overflow:ellipsis;max-width:380px;">▸ ${d.targetHeadline}</div>
        </div>
      ` : ''

      return `
        <div style="
          background:rgba(10,12,18,0.92);
          backdrop-filter:blur(12px);
          border:1px solid ${threat >= 5 ? 'rgba(255,60,60,0.25)' : 'rgba(0,255,204,0.15)'};
          border-left:3px solid ${driftLevelColor};
          border-radius:6px;
          padding:14px 18px;
          font-family:'JetBrains Mono','Fira Code','SF Mono',monospace;
          color:#e0e0e0;
          min-width:320px;
          max-width:420px;
          line-height:1.5;
          box-shadow:0 8px 32px rgba(0,0,0,0.5);
        ">
          <div style="font-size:9px;text-transform:uppercase;letter-spacing:2px;color:#607080;margin-bottom:8px;">
            NARRATIVE DRIFT ANALYSIS
          </div>
          ${gdeltActorSummary ? `
            <div style="font-size:13px;font-weight:700;color:#ff9090;margin-bottom:6px;">${gdeltActorSummary}</div>
          ` : (d.sourceCountry && d.targetCountry) ? `
            <div style="font-size:12px;margin-bottom:6px;">
              <span style="color:#00ffcc;">${d.sourceCountry}</span>
              <span style="color:#607080;margin:0 6px;">→</span>
              <span style="color:${framingColor};">${d.targetCountry}</span>
            </div>
          ` : ''}
          <div style="font-size:10px;color:#8090a0;margin-bottom:${(d.sourceCountry || gdeltActorSummary) ? '10' : '6'}px;">
            ${d.sourceName || d.sourceCountry || '?'} → ${d.targetSourceName || d.targetCountry || '?'}
          </div>
          ${headlines}
          <div style="display:grid;grid-template-columns:1fr 1fr;gap:8px;margin-bottom:10px;">
            <div>
              <div style="font-size:8px;text-transform:uppercase;letter-spacing:1px;color:#506070;">Threat</div>
              <div style="font-size:11px;color:${driftLevelColor};font-weight:600;">${driftLevel}</div>
            </div>
            <div>
              <div style="font-size:8px;text-transform:uppercase;letter-spacing:1px;color:#506070;">Framing</div>
              <div style="font-size:11px;color:${framingColor};font-weight:600;">${framing.toUpperCase()}</div>
            </div>
            <div>
              <div style="font-size:8px;text-transform:uppercase;letter-spacing:1px;color:#506070;">Sentiment</div>
              <div style="font-size:11px;">${sentimentShift}</div>
            </div>
            <div>
              <div style="font-size:8px;text-transform:uppercase;letter-spacing:1px;color:#506070;">Semantic Match</div>
              <div style="font-size:11px;color:${similarity > 85 ? '#00ffcc' : '#ffd700'};">${similarity}%</div>
            </div>
          </div>
          ${explanation ? `
            <div style="font-size:10px;color:#8898a8;border-top:1px solid rgba(255,255,255,0.06);padding-top:8px;font-style:italic;">
              "${explanation}"
            </div>
          ` : ''}
          <div style="margin-top:10px;">
            <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:4px;">
              <div style="font-size:8px;text-transform:uppercase;letter-spacing:1px;color:#506070;">Score ${threat.toFixed(1)}/10</div>
              <div style="font-size:8px;color:#506070;">conf ${Math.round((d.arcConfidence || 0) * 100)}%</div>
            </div>
            <div style="width:100%;height:4px;background:rgba(255,255,255,0.06);border-radius:2px;overflow:hidden;">
              <div style="width:${Math.round(threat * 10)}%;height:100%;background:linear-gradient(90deg,#6088a0,${driftLevelColor});border-radius:2px;"></div>
            </div>
            ${d.signalBreakdown ? `
              <div style="display:flex;gap:8px;margin-top:5px;font-size:8px;color:#506070;">
                <span>CTX:${d.signalBreakdown.threatContext}</span>
                <span>DFT:${d.signalBreakdown.driftEffective}</span>
                ${d.signalBreakdown.gdeltBonus > 0 ? `<span>GDT:${d.signalBreakdown.gdeltBonus}</span>` : ''}
              </div>
            ` : ''}
          </div>
          ${gdeltActorSummary ? `
            <div style="margin-top:10px;padding-top:8px;border-top:1px solid rgba(255,45,45,0.2);">
              <div style="font-size:8px;text-transform:uppercase;letter-spacing:1px;color:#ff6060;margin-bottom:5px;">CONFLICT INTELLIGENCE</div>
              ${gdeltEventDescription ? `<div style="font-size:10px;color:#c08080;margin-bottom:3px;">${gdeltEventDescription}</div>` : ''}
              <div style="display:flex;gap:10px;margin-top:3px;">
                ${gdeltQuadClassLabel ? `<span style="font-size:9px;color:#a06060;text-transform:uppercase;">${gdeltQuadClassLabel}</span>` : ''}
                ${gdeltGoldsteinScale != null ? `<span style="font-size:9px;color:${gdeltGoldsteinScale < -7 ? '#ff2d2d' : '#ff8060'};">Goldstein: ${gdeltGoldsteinScale.toFixed(1)}</span>` : ''}
              </div>
            </div>
          ` : ''}
        </div>
      `
    }

    // Fallback: legacy tooltip for simple arcs without drift data
    const isSegment = d.sourceName !== undefined || d.targetSourceName !== undefined
    const segmentInfo = isSegment ? `
      <div style="color:#a78bfa;font-size:8px;letter-spacing:0.1em;margin-bottom:2px;text-transform:uppercase;">
        HOP ${(d.segmentIndex || 0) + 1} of ${d.totalSegments || '?'}
      </div>
      <div style="font-size:10px;margin-bottom:4px;">
        ${d.sourceName || 'Unknown'} → ${d.targetSourceName || 'Unknown'}
      </div>
    ` : ''
    return `
      <div style="
        background:rgba(10,12,20,0.92);
        border:1px solid rgba(0,240,255,0.3);
        border-radius:4px;
        padding:8px 12px;
        font-family:'JetBrains Mono',monospace;
        font-size:11px;
        color:#e0e6ed;
        line-height:1.4;
        box-shadow:0 0 20px rgba(0,240,255,0.15);
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
          <span style="color:#22c55e;font-size:10px;font-weight:700;">${Math.round((d.strength || 0) * 100)}%</span>
        </div>` : ''}
      </div>
    `
  }

  // -------------------------------------------------------
  // Network Arc Tooltip — shows only available data, never "?"
  // -------------------------------------------------------

  _buildNetworkArcTooltip(d) {
    const score = d.veritasThreatScore || 0
    const strength = d.strength || 0
    const types = (d.connectionTypes || []).map(t => this._connectionTypeBadge(t)).join(' ')

    const driftLevelColor = score >= 7 ? '#ff2d2d' : score >= 5 ? '#ff8c00' : score >= 3 ? '#ffd700' : '#6088a0'
    const driftLevel = score >= 7 ? 'CRITICAL' : score >= 5 ? 'HIGH' : score >= 3 ? 'MODERATE' : 'LOW'

    const sourceName = d.sourceName || d.sourceCountry || 'Source'
    const targetName = d.targetSourceName || d.targetCountry || 'Target'

    // Build optional sections — only render what exists
    let headlines = ''
    if (d.sourceHeadline || d.targetHeadline) {
      headlines = `<div style="font-size:10px;margin-bottom:8px;padding-bottom:8px;border-bottom:1px solid rgba(255,255,255,0.06);">`
      if (d.sourceHeadline) headlines += `<div style="color:#00ffcc;margin-bottom:3px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;max-width:380px;">&#9656; ${d.sourceHeadline}</div>`
      if (d.targetHeadline) headlines += `<div style="color:#c0d0e0;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;max-width:380px;">&#9656; ${d.targetHeadline}</div>`
      headlines += `</div>`
    }

    let analysisGrid = ''
    const cells = []
    if (d.framing) cells.push({ label: 'Framing', value: d.framing.toUpperCase(), color: this._getFramingColor(d.framing) })
    if (d.sentimentShift) cells.push({ label: 'Sentiment', value: d.sentimentShift, color: '#e0e0e0' })
    if (d.semanticSimilarity) cells.push({ label: 'Semantic Match', value: `${d.semanticSimilarity}%`, color: d.semanticSimilarity > 85 ? '#00ffcc' : '#ffd700' })
    if (d.depth) cells.push({ label: 'Depth', value: `${d.depth}`, color: '#8090a0' })

    if (cells.length > 0) {
      analysisGrid = `<div style="display:grid;grid-template-columns:1fr 1fr;gap:8px;margin-bottom:10px;">`
      cells.forEach(c => {
        analysisGrid += `<div><div style="font-size:8px;text-transform:uppercase;letter-spacing:1px;color:#506070;">${c.label}</div><div style="font-size:11px;color:${c.color};font-weight:600;">${c.value}</div></div>`
      })
      analysisGrid += `</div>`
    }

    let gdeltSection = ''
    if (d.actorSummary || d.eventDescription) {
      gdeltSection = `
        <div style="margin-top:10px;padding-top:8px;border-top:1px solid rgba(255,45,45,0.2);">
          <div style="font-size:8px;text-transform:uppercase;letter-spacing:1px;color:#ff6060;margin-bottom:5px;">CONFLICT INTELLIGENCE</div>
          ${d.actorSummary ? `<div style="font-size:10px;color:#ff9090;font-weight:600;margin-bottom:3px;">${d.actorSummary}</div>` : ''}
          ${d.eventDescription ? `<div style="font-size:10px;color:#c08080;">${d.eventDescription}</div>` : ''}
          ${d.goldsteinScale != null ? `<div style="font-size:9px;color:${d.goldsteinScale < -7 ? '#ff2d2d' : '#ff8060'};margin-top:3px;">Goldstein: ${d.goldsteinScale.toFixed(1)}</div>` : ''}
        </div>`
    }

    let entitySection = ''
    if (d.sharedEntities && d.sharedEntities.length > 0) {
      entitySection = `
        <div style="margin-top:8px;padding-top:8px;border-top:1px solid rgba(0,255,204,0.1);">
          <div style="font-size:8px;text-transform:uppercase;letter-spacing:1px;color:#00c0a0;margin-bottom:4px;">SHARED ENTITIES (${d.sharedEntityCount || d.sharedEntities.length})</div>
          <div style="font-size:10px;color:#80c0b0;">${d.sharedEntities.join(', ')}</div>
        </div>`
    }

    return `
      <div style="
        background:rgba(10,12,18,0.92);backdrop-filter:blur(12px);
        border:1px solid ${score >= 5 ? 'rgba(255,60,60,0.25)' : 'rgba(0,255,204,0.15)'};
        border-left:3px solid ${driftLevelColor};
        border-radius:6px;padding:14px 18px;
        font-family:'JetBrains Mono','Fira Code','SF Mono',monospace;
        color:#e0e0e0;min-width:320px;max-width:420px;line-height:1.5;
        box-shadow:0 8px 32px rgba(0,0,0,0.5);
      ">
        <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:8px;">
          <div style="font-size:9px;text-transform:uppercase;letter-spacing:2px;color:#607080;">NARRATIVE NETWORK</div>
          <div style="display:flex;gap:4px;">${types}</div>
        </div>
        <div style="font-size:12px;margin-bottom:6px;">
          <span style="color:#00ffcc;">${sourceName}</span>
          <span style="color:#607080;margin:0 6px;">&rarr;</span>
          <span style="color:#c0d0e0;">${targetName}</span>
        </div>
        ${headlines}
        ${analysisGrid}
        <div style="margin-top:8px;">
          <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:4px;">
            <div style="font-size:8px;text-transform:uppercase;letter-spacing:1px;color:#506070;">Threat ${score.toFixed(1)}/10 &middot; ${driftLevel}</div>
            <div style="font-size:8px;color:#506070;">strength ${Math.round(strength * 100)}%</div>
          </div>
          <div style="width:100%;height:4px;background:rgba(255,255,255,0.06);border-radius:2px;overflow:hidden;">
            <div style="width:${Math.round(score * 10)}%;height:100%;background:linear-gradient(90deg,#6088a0,${driftLevelColor});border-radius:2px;"></div>
          </div>
        </div>
        ${gdeltSection}
        ${entitySection}
      </div>`
  }

  _connectionTypeBadge(type) {
    const badges = {
      narrative_route:      { label: 'ROUTE',    color: '#a855f7' },
      gdelt_event:          { label: 'GDELT',    color: '#ef4444' },
      embedding_similarity: { label: 'SEMANTIC',  color: '#3b82f6' },
      shared_entities:      { label: 'ENTITIES',  color: '#22c55e' }
    }
    const b = badges[type] || { label: type.toUpperCase(), color: '#6b7280' }
    return `<span style="font-size:7px;padding:2px 5px;border-radius:3px;background:${b.color}20;color:${b.color};border:1px solid ${b.color}40;letter-spacing:0.5px;">${b.label}</span>`
  }

  // Returns the dominant (highest-weight) connection type for visual styling.
  // Weight order: narrative_route > gdelt_event > embedding_similarity > shared_entities
  _dominantConnectionType(d) {
    const types = d.connectionTypes || []
    if (types.length === 0) return null
    if (types.length === 1) return types[0]
    const priority = ['narrative_route', 'gdelt_event', 'embedding_similarity', 'shared_entities']
    for (const p of priority) {
      if (types.includes(p)) return p
    }
    return types[0]
  }

  _isValidPoint(p) {
    if (p.lat == null || p.lng == null) return false
    if (Math.abs(p.lat) > 90 || Math.abs(p.lng) > 180) return false
    if (Math.abs(p.lat) < 1 && Math.abs(p.lng) < 1) return false
    return true
  }

  _isValidArc(arc) {
    const { startLat, startLng, endLat, endLng } = arc
    if (startLat == null || startLng == null || endLat == null || endLng == null) return false
    // Out-of-range coordinates (GDELT parsing bug)
    if (Math.abs(startLat) > 90 || Math.abs(endLat) > 90) return false
    if (Math.abs(startLng) > 180 || Math.abs(endLng) > 180) return false
    // Null island
    if (Math.abs(startLat) < 1 && Math.abs(startLng) < 1) return false
    if (Math.abs(endLat) < 1 && Math.abs(endLng) < 1) return false
    // Too short (spike/needle) — within 2° in both axes
    if (Math.abs(startLat - endLat) < 2 && Math.abs(startLng - endLng) < 2) return false
    return true
  }

  _hexToRgba(hex, alpha) {
    const h = hex.replace('#', '')
    if (h.length !== 6) return hex
    const r = parseInt(h.slice(0, 2), 16)
    const g = parseInt(h.slice(2, 4), 16)
    const b = parseInt(h.slice(4, 6), 16)
    return `rgba(${r},${g},${b},${alpha})`
  }

  // -------------------------------------------------------
  // Narrative Timelapse — Cinematic Playback Engine
  // -------------------------------------------------------

  _onTimelapseToggle() {
    if (this._timelapseState) {
      this._exitTimelapse()
    } else {
      // Toolbar button always triggers exploration mode
      this._timelapseContext = { mode: 'exploration', routeId: null }
      setTimeout(() => this._startTimelapse(), 150)
    }
  }

  // Start story mode timelapse for a specific route (called from arc click / article)
  startStoryTimelapse(routeId) {
    if (this._timelapseState) this._exitTimelapseImmediate()
    this._timelapseContext = { mode: 'story', routeId: routeId }
    setTimeout(() => this._startTimelapse(), 150)
  }

  // ---- EXPLORATION MODE: top 3 routes, multi-narrative overview ----
  _prepareExplorationData() {
    const allArcs = this._allArcs || []
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

  // ---- STORY MODE: single route, ALL hops, chronological ----
  _prepareStoryData(routeId) {
    const allArcs = this._allArcs || []

    // Find all segments belonging to this route
    const routeSegments = allArcs.filter(seg =>
      String(seg.routeId) === String(routeId)
    )

    if (routeSegments.length === 0) {
      // Fallback: try to find the route in _allRoutes and use its segments
      const route = (this._allRoutes || []).find(r =>
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

  _startTimelapse() {
    if (!this._globe) return
    if (this._journeyActive) return

    const ctx = this._timelapseContext
    const segments = ctx.mode === 'story' && ctx.routeId
      ? this._prepareStoryData(ctx.routeId)
      : this._prepareExplorationData()

    if (segments.length === 0) return

    // Story mode: slower pacing (15s) for focused narrative. Exploration: 12s.
    const duration = ctx.mode === 'story' ? 15000 : 12000

    console.log(`[Timelapse] Starting ${ctx.mode} mode — ${segments.length} segments, ${duration / 1000}s${ctx.routeId ? `, route: ${ctx.routeId}` : ''}`)

    this._timelapseState = {
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

    // Save current state for clean restore
    this._preTimelapseState = {
      arcsData: this._cloneLayer(this._globe.arcsData() || []),
      hexBinPointsData: this._cloneLayer(this._globe.hexBinPointsData() || []),
      ringsData: this._cloneLayer(this._globe.ringsData() || []),
      pointOfView: { ...(this._globe.pointOfView?.() || { lat: 20, lng: 10, altitude: 2.5 }) },
      autoRotate: this._globe.controls().autoRotate,
      autoRotateSpeed: this._globe.controls().autoRotateSpeed,
      packetVisible: this._packetGroup ? this._packetGroup.visible !== false : true
    }

    // Clear globe for clean canvas
    this._globe.arcsData([]).ringsData([])
    if (this._packetGroup) this._packetGroup.visible = false
    this._globe.controls().autoRotate = false

    // Set arc callbacks ONCE
    this._applyTimelapseCallbacks()

    this._enterTimelapseMode()

    // Dispatch state
    window.dispatchEvent(new CustomEvent("veritas:timelapseState", {
      detail: { active: true }
    }))

    // Cinematic start: brief settle before first arc (300ms anticipation)
    this._timelapseState.startedAt = performance.now() + 300
    setTimeout(() => this._timelapseFrame(), 300)
  }

  _timelapseFrame() {
    const state = this._timelapseState
    if (!state || !state.playing) return

    const duration = state._duration || 12000
    const elapsed = performance.now() - state.startedAt
    state.currentTime = Math.min(elapsed / duration, 1.0)

    // Reveal segments that should be visible at this time
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

    // Fire emergence effect for newly revealed arcs
    newlyRevealed.forEach(seg => this._onTimelapseArcReveal(seg))

    // Track the latest arc for visual highlighting
    if (newlyRevealed.length > 0) {
      const latest = newlyRevealed[newlyRevealed.length - 1]
      state._latestArcId = latest.id || latest._timestamp
    }

    // Update opacity on all active arcs (fast 300ms fade-in)
    const now = performance.now()
    state.activeArcs.forEach(arc => {
      arc._opacity = Math.min((now - arc._revealTime) / 300, 1.0)
      // Mark whether this is the latest arc for highlight callback
      arc._isLatest = (arc.id || arc._timestamp) === state._latestArcId
    })

    // Only push arcsData when new arcs appeared — avoids flicker from rebuilding every frame.
    // The arc callbacks read _opacity etc. from the data objects directly.
    if (newlyRevealed.length > 0) {
      this._globe.arcsData([...state.activeArcs])
    }

    // Camera: smoothly follow the latest revealed segment
    if (newlyRevealed.length > 0) {
      this._smoothTimelapseCamera(newlyRevealed[newlyRevealed.length - 1])
    }

    // Update overlay
    if (newlyRevealed.length > 0) {
      this._updateTimelapseOverlay(newlyRevealed[newlyRevealed.length - 1], state)
    }

    // Update progress bar
    this._updateTimelapseProgress(state)

    // Continue or end
    if (state.currentTime >= 1.0) {
      setTimeout(() => this._endTimelapse(), 1500)
    } else {
      requestAnimationFrame(() => this._timelapseFrame())
    }
  }

  // Set arc callbacks ONCE at timelapse start. The callbacks read dynamic
  // properties (_opacity, _revealTime, _isLatest) from the arc data objects,
  // so they produce correct visuals without being re-registered every frame.
  _applyTimelapseCallbacks() {
    if (!this._globe) return

    this._globe
      .arcColor(d => {
        const opacity = d._opacity != null ? d._opacity : 1
        const threat = d.veritasThreatScore || 0
        const vis = d.visibilityWeight || 0.3

        // Latest arc gets a subtle brightness boost
        const boost = d._isLatest ? 1.3 : 1.0

        // Threat-based target color (same logic as main arc color)
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

        // visibilityWeight modulates base opacity
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

        // Low threat + low visibility: single neutral color
        if (threat < 2 && vis < 0.5) {
          return `rgba(${sourceColor.r}, ${sourceColor.g}, ${sourceColor.b}, ${sourceColor.a})`
        }

        const stops = 8
        const colors = []
        for (let i = 0; i < stops; i++) {
          const t = i / (stops - 1)
          const eased = t * t
          colors.push(this._interpolateColor(sourceColor, targetColor, eased))
        }
        return colors
      })
      .arcStroke(d => {
        const baseThickness = 0.6 + (d.driftIntensity || 0) * 1.2
        const revealScale = d._opacity != null ? d._opacity : 1
        // Latest arc: 40% thicker for visual focus
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

  // Store default arc stroke logic so we can restore it
  _arcStrokeDefault(d) {
    if (this._selectedArcArticleId && String(d.articleId) === String(this._selectedArcArticleId)) {
      return 2.5
    }
    // Network arcs: stroke by dominant connection type
    if (d.connectionTypes) {
      const dom = this._dominantConnectionType(d)
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

  _onTimelapseArcReveal(arc) {
    if (!this._globe) return

    // Flash a ring at the SOURCE location
    const currentRings = this._globe.ringsData() || []
    const framingColor = this._getFramingColor(arc.framingShift)
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

    // High-drift arc: shockwave ring at target too
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

  _smoothTimelapseCamera(segment) {
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

  // -------------------------------------------------------
  // Timelapse Overlay HUD
  // -------------------------------------------------------

  _enterTimelapseMode() {
    if (this._timelapseOverlay) return

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

        <!-- Controls — pointer-events: auto + z-index so clicks reach buttons -->
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

    const globeContainer = this.element
    globeContainer.style.position = 'relative'
    globeContainer.appendChild(overlay)
    this._timelapseOverlay = overlay

    // Wire up controls
    document.getElementById('tl-btn-playpause').addEventListener('click', () => this._toggleTimelapsePause())
    document.getElementById('tl-btn-restart').addEventListener('click', () => this._restartTimelapse())
    document.getElementById('tl-btn-exit').addEventListener('click', () => this._exitTimelapse())

    // Set timeline range labels
    const state = this._timelapseState
    if (state && state.segments.length > 0) {
      const first = state.segments[0]
      const last = state.segments[state.segments.length - 1]
      const startEl = document.getElementById('tl-time-start')
      const endEl = document.getElementById('tl-time-end')
      if (startEl) startEl.textContent = this._formatTimelapseDate(first._timestamp)
      if (endEl) endEl.textContent = this._formatTimelapseDate(last._timestamp)
    }

    // Set header text based on mode
    const ctx = this._timelapseContext
    const routeNameEl = document.getElementById('tl-route-name')
    if (ctx.mode === 'story' && routeNameEl) {
      // Find the route to display its headline
      const route = (this._allRoutes || []).find(r =>
        String(r.routeId || r.id) === String(ctx.routeId)
      )
      const headline = route?.headline || route?.sourceHeadline || `Route ${ctx.routeId}`
      routeNameEl.textContent = headline
      // Update the mode label
      const headerEl = document.getElementById('tl-header')
      if (headerEl) {
        const modeLabel = headerEl.querySelector('div')
        if (modeLabel) modeLabel.innerHTML = '&#9654; STORY MODE &#9664;'
      }
    }

    // Fade in overlay elements
    requestAnimationFrame(() => {
      ['tl-header', 'tl-event-card', 'tl-progress', 'tl-stats', 'tl-controls'].forEach(id => {
        const el = document.getElementById(id)
        if (el) el.style.opacity = '1'
      })
    })
  }

  _formatTimelapseDate(timestamp) {
    if (!timestamp) return ''
    const d = new Date(timestamp)
    return d.toLocaleDateString('en-US', { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' })
  }

  _updateTimelapseOverlay(segment, state) {
    const framingColor = this._getFramingColor(segment.framingShift)

    // Flow: Country -> Country
    const flowEl = document.getElementById('tl-flow')
    if (flowEl) {
      flowEl.innerHTML = `
        <span style="color: #b0c4d8;">${segment.sourceCountry || '?'}</span>
        <span style="color: #404850; margin: 0 8px;">&rarr;</span>
        <span style="color: ${framingColor};">${segment.targetCountry || '?'}</span>
      `
    }

    // Sources
    const srcEl = document.getElementById('tl-sources')
    if (srcEl) {
      srcEl.textContent = `${segment.sourceName || '?'} \u2192 ${segment.targetSourceName || '?'}`
    }

    // Headlines
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

    // Metrics
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

    // Explanation
    const expEl = document.getElementById('tl-explanation')
    if (expEl && segment.framingExplanation) {
      expEl.textContent = `"${segment.framingExplanation}"`
      expEl.style.display = 'block'
    } else if (expEl) {
      expEl.style.display = 'none'
    }

    // Stats
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

    // Animate the event card entrance
    const card = document.getElementById('tl-event-card')
    if (card) {
      card.style.opacity = '1'
      card.style.transform = 'translateY(0)'
    }
  }

  _updateTimelapseProgress(state) {
    const progBar = document.getElementById('tl-progress-bar')
    if (progBar) {
      progBar.style.width = `${Math.round(state.currentTime * 100)}%`
    }
  }

  // -------------------------------------------------------
  // Timelapse Controls
  // -------------------------------------------------------

  _toggleTimelapsePause() {
    const state = this._timelapseState
    if (!state) return

    state.playing = !state.playing
    const btn = document.getElementById('tl-btn-playpause')

    if (state.playing) {
      const pausedDuration = performance.now() - state._pausedAt
      state.startedAt += pausedDuration
      if (btn) btn.textContent = 'Pause'
      this._timelapseFrame()
    } else {
      state._pausedAt = performance.now()
      if (btn) btn.textContent = 'Play'
    }
  }

  _restartTimelapse() {
    // Preserve the current context so replay uses the same mode/route
    const ctx = this._timelapseState
      ? { mode: this._timelapseState._mode, routeId: this._timelapseState._routeId }
      : this._timelapseContext
    this._exitTimelapse()
    this._timelapseContext = ctx
    setTimeout(() => this._startTimelapse(), 300)
  }

  _exitTimelapse() {
    const state = this._timelapseState
    if (state) state.playing = false
    this._timelapseState = null

    // Fade out overlay
    ['tl-header', 'tl-event-card', 'tl-progress', 'tl-stats', 'tl-controls'].forEach(id => {
      const el = document.getElementById(id)
      if (el) el.style.opacity = '0'
    })

    // Dispatch state
    window.dispatchEvent(new CustomEvent("veritas:timelapseState", {
      detail: { active: false }
    }))

    // Restore original globe state after fade-out
    setTimeout(() => {
      this._restoreTimelapseState()
      if (this._timelapseOverlay) {
        this._timelapseOverlay.remove()
        this._timelapseOverlay = null
      }
    }, 600)
  }

  // Synchronous, instant exit — no fade animation. Used when switching
  // from one timelapse mode directly into another (e.g. exploration → story).
  _exitTimelapseImmediate() {
    const state = this._timelapseState
    if (state) state.playing = false
    this._timelapseState = null

    this._restoreTimelapseState()
    if (this._timelapseOverlay) {
      this._timelapseOverlay.remove()
      this._timelapseOverlay = null
    }

    window.dispatchEvent(new CustomEvent("veritas:timelapseState", {
      detail: { active: false }
    }))
  }

  _endTimelapse() {
    // Called when animation completes naturally — show final state briefly
    const state = this._timelapseState
    if (state) state.playing = false

    const btn = document.getElementById('tl-btn-playpause')
    if (btn) {
      btn.textContent = 'Replay'
      // Replace the pause/play handler with a one-shot replay that preserves context
      btn.onclick = () => {
        btn.onclick = null
        this._restartTimelapse()
      }
    }
  }

  _restoreTimelapseState() {
    if (!this._globe || !this._preTimelapseState) return

    const state = this._preTimelapseState

    // Restore the original arc color/stroke/dash callbacks
    this._globe
      .arcColor(d => this._arcColorWithDrift(d))
      .arcStroke(d => this._arcStrokeDefault(d))
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

    // Restore data layers
    this._globe
      .hexBinPointsData(this._cloneLayer(state.hexBinPointsData || []))
      .arcsData(this._cloneLayer(state.arcsData || []))
      .ringsData(this._cloneLayer(state.ringsData || []))

    if (state.pointOfView) this._globe.pointOfView(state.pointOfView, 1000)

    const controls = this._globe.controls()
    controls.autoRotate = state.autoRotate ?? true
    controls.autoRotateSpeed = state.autoRotateSpeed ?? 0.4

    if (this._packetGroup) this._packetGroup.visible = state.packetVisible !== false
    if (this._globe) this._updatePackets()

    this._preTimelapseState = null
  }
}
