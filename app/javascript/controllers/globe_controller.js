import { Controller } from "@hotwired/stimulus"
import consumer from "channels/consumer"
import { dominantConnectionType, isValidPoint, isValidArc } from "globe/color_utils"
import { showHopDetails } from "globe/hop_details_panel"
import { PacketAnimator } from "globe/packet_animator"
import { RouteChoiceMenu } from "globe/route_choice_menu"
import { HeatmapManager } from "globe/heatmap_manager"
import { createArcColorCallback, createPointColorCallback, buildArcTooltip } from "globe/arc_styles"
import { NetworkView } from "globe/network_view"
import { TimelapseEngine } from "globe/timelapse_engine"
import { GlobeLighting } from "globe/globe_lighting"
import { GlobeCamera } from "globe/globe_camera"
import { HexLayer } from "globe/hex_layer"
import { GlobeInteractions } from "globe/globe_interactions"
import { GlobeBroadcast } from "globe/globe_broadcast"
import { GlobeEventBus } from "globe/globe_events"
import { TemporalFilter } from "globe/temporal_filter"

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
    this._abortController    = null
    this._globeMode          = "global"
    this._networkCenterArticleId = null
    this._networkData        = null
    this._hideIsolated       = false
    this._journeyActive      = false
    this._allRoutes          = []
    this._preJourneyState    = null
    this._selectedArcArticleId = null

    // Module instances (globe-independent)
    this._lighting     = new GlobeLighting(() => this._globe)
    this._camera       = new GlobeCamera(() => this._globe)
    this._hexLayer     = new HexLayer(this)
    this._interactions = new GlobeInteractions(this)
    this._broadcast    = new GlobeBroadcast(this)
    this._eventBus     = new GlobeEventBus()
    this._routeChoiceMenu = new RouteChoiceMenu(this.element)
    this._networkView  = new NetworkView(this)
    this._timelapseEngine = new TimelapseEngine(this)
    this._temporalFilter = new TemporalFilter()

    const controller = this
    this._arcState = {
      get selectedArcArticleId() { return controller._selectedArcArticleId },
      get currentPerspective() { return controller._currentPerspective }
    }
    this._arcColorFn  = createArcColorCallback(this._arcState)
    this._pointColorFn = createPointColorCallback(this._arcState)

    this._eventBus.bind(this)
    this._initGlobe()
    this._broadcast.subscribe(consumer)
  }

  disconnect() {
    delete this.element.__controller
    this._broadcast.unsubscribe()
    this._eventBus.unbind()
    if (this._timelapseEngine?.state) this._timelapseEngine.state.playing = false
    this._camera.dispose()
    this._heatmapManager?.dispose()
    if (this._onMouseMove) this.element.removeEventListener('mousemove', this._onMouseMove)
    if (this._onMouseLeave) this.element.removeEventListener('mouseleave', this._onMouseLeave)
    if (this._resizeObserver) this._resizeObserver.disconnect()
    if (this._globe) {
      cancelAnimationFrame(this._animFrame)
      this._globe._destructor && this._globe._destructor()
    }
    this._packetAnimator?.dispose()
    this._routeChoiceMenu?.hide()
  }

  get globe() { return this._globe }

  // -------------------------------------------------------
  // Public API (used by modules)
  // -------------------------------------------------------

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
      packetVisible: this._packetAnimator?.group ? this._packetAnimator?.group.visible !== false : true
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
    if (this._packetAnimator?.group) this._packetAnimator.group.visible = state.packetVisible !== false
    if (this._globe) this._packetAnimator?.update()
  }

  getRoute(routeId) {
    return (this._allRoutes || []).find((route) => String(route.routeId || route.id) === String(routeId))
  }

  getScreenPosition(lat, lng) {
    if (!this._globe) return null
    const coords = this._globe.getScreenCoords(lat, lng)
    return coords ? { x: coords.x, y: coords.y } : null
  }

  // -------------------------------------------------------
  // Globe Initialization
  // -------------------------------------------------------

  async _initGlobe() {
    const Globe = (await import("globe.gl")).default
    const container = this.element

    this._globe = Globe()
      .globeImageUrl("/globe/earth-blue-marble.jpg")
      .bumpImageUrl("/globe/earth-topology.png")
      .backgroundImageUrl("/globe/night-sky.png")
      .width(container.clientWidth)
      .height(container.clientHeight)
      .atmosphereColor("#00f0ff")
      .atmosphereAltitude(0.25)
      // Hex-bin layer
      .hexBinPointsData([])
      .hexBinPointLat(d => d.lat)
      .hexBinPointLng(d => d.lng)
      .hexBinPointWeight(d => this._hexLayer.weight(d))
      .hexBinResolution(3)
      .hexBinMerge(true)
      .hexMargin(0.3)
      .hexTopColor(d => this._hexLayer.color(d, 'top'))
      .hexSideColor(d => this._hexLayer.color(d, 'side'))
      .hexAltitude(d => Math.min(0.15, 0.005 + (d.sumWeight * 0.003)))
      .hexTransitionDuration(800)
      .onHexHover(hex => this._hexLayer.onHover(hex))
      .onHexClick(hex => this._hexLayer.onClicked(hex))
      // Arcs layer
      .arcColor(d => this._arcColorFn(d))
      .arcDashLength(d => {
        if (d.arcDashLength != null) return d.arcDashLength
        if (d.connectionTypes) {
          const dom = dominantConnectionType(d)
          if (dom === 'narrative_route') return 0.4
          if (dom === 'embedding_similarity') return 0.2
          return 0
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
        if (d.connectionTypes) {
          const dom = dominantConnectionType(d)
          if (dom === 'narrative_route') return 0.15
          if (dom === 'embedding_similarity') return 0.15
          return 0
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
        if (d.connectionTypes) {
          const dom = dominantConnectionType(d)
          if (dom === 'narrative_route') {
            const strength = d.strength || 0.5
            return Math.round(3000 - (strength * 1500))
          }
          return 0
        }
        if (d.driftIntensity != null) {
          const intensity = d.driftIntensity
          return Math.round(4000 - (intensity * 2800))
        }
        return d.tier === 1 ? 2500 : 0
      })
      .arcStroke(d => {
        if (this._selectedArcArticleId && String(d.articleId) === String(this._selectedArcArticleId)) return 2.5
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
        if (d.visibilityWeight != null) {
          const vis = d.visibilityWeight || 0.3
          const base = d.tier === 1 ? 1.0 : (d.tier === 2 ? 0.4 : 0.3)
          return base + (vis * 1.0)
        }
        if (d.tier === 1) return 1.2
        if (d.tier === 2) return 0.5
        return d.thickness ? Math.min(d.thickness, 1.0) : 0.4
      })
      .onArcHover(arc => this._interactions.onArcHover(arc))
      .onArcClick(arc => this._interactions.onArcClicked(arc))
      // Tooltips
      .hexLabel(d => this._hexLayer.buildTooltip(d))
      .arcLabel(d => buildArcTooltip(d))
      // Heatmap layer
      .heatmapsData([])
      .heatmapPointLat('lat')
      .heatmapPointLng('lng')
      .heatmapPointWeight('weight')
      .heatmapTopAltitude(0.12)
      .heatmapBandwidth(3.2)
      .heatmapColorFn(() => t => {
        if (t < 0.05) return 'rgba(0,0,0,0)'
        const a = Math.min(1, t * 1.8)
        if (t < 0.2) return `rgba(40,0,${Math.round(120 + t * 400)},${a})`
        if (t < 0.45) return `rgba(${Math.round((t - 0.2) * 1020)},0,${Math.round(200 - (t - 0.2) * 600)},${a})`
        if (t < 0.7) return `rgba(255,${Math.round((t - 0.45) * 440)},0,${Math.min(1, a + 0.1)})`
        return `rgba(255,${Math.round(110 + (t - 0.7) * 483)},${Math.round((t - 0.7) * 400)},1)`
      })
      .heatmapsTransitionDuration(800)
      // Threat rings
      .ringsData([])
      .ringLat("lat")
      .ringLng("lng")
      .ringColor(d => t => {
        const cfg = THREAT_RING[d.threat] || THREAT_RING[1]
        const hex = cfg.color
        const r = parseInt(hex.slice(1, 3), 16)
        const g = parseInt(hex.slice(3, 5), 16)
        const b = parseInt(hex.slice(5, 7), 16)
        return `rgba(${r},${g},${b},${Math.max(0, (1 - t) * 0.3)})`
      })
      .ringMaxRadius("maxRadius")
      .ringPropagationSpeed("propagationSpeed")
      .ringRepeatPeriod("repeatPeriod")
      (container)

    // Lighting & camera
    await this._lighting.setup()

    const controls = this._globe.controls()
    controls.autoRotate = true
    controls.autoRotateSpeed = 0.4
    controls.enableZoom = true
    controls.minDistance = 150
    controls.maxDistance = 500
    this._globe.pointOfView({ lat: 20, lng: 10, altitude: 2.5 }, 0)

    // Init globe-dependent modules
    this._packetAnimator = new PacketAnimator(this._globe)
    this._heatmapManager = new HeatmapManager(this._globe)

    await this._loadData()

    this._resizeObserver = new ResizeObserver(() => {
      this._globe.width(container.clientWidth).height(container.clientHeight)
    })
    this._resizeObserver.observe(container)

    // Mousemove → heatmap tooltip
    this._onMouseMove = (e) => this._heatmapManager.handleHover(e, container)
    this._onMouseLeave = () => this._heatmapManager.hideTooltip()
    container.addEventListener('mousemove', this._onMouseMove)
    container.addEventListener('mouseleave', this._onMouseLeave)
  }

  // -------------------------------------------------------
  // Data Loading
  // -------------------------------------------------------

  _loadData() {
    if (this._journeyActive) return Promise.resolve()
    if (this._globeMode === "network" && this._networkCenterArticleId) {
      return this._networkView.loadArticleNetwork(this._networkCenterArticleId)
    }
    return this._networkView.loadGlobalNetwork()
  }

  async _fetchAndRender() {
    if (this._journeyActive) return
    this._abortController?.abort()
    this._abortController = new AbortController()
    const signal = this._abortController.signal

    try {
      const params = new URLSearchParams()
      if (this._currentTopic) params.set("topic", this._currentTopic)
      if (this._currentTimestamp) params.set("to", this._currentTimestamp)
      params.set("view", "segments")

      const query = params.toString()
      const url = query ? `${this.dataUrlValue}?${query}` : this.dataUrlValue
      const response = await fetch(url, { signal })
      const data = await response.json()

      this._heatmapManager.baseData = data.heatmap || []
      this._heatmapManager.clusters = data.heatmapClusters || []
      this._allPoints = (data.points || []).filter(p => isValidPoint(p))
      this._allArcs = (data.arcs || []).filter(a => isValidArc(a))
      this._allRoutes = data.routes || []

      // Feed temporal filter for client-side DVR replay
      this._temporalFilter.setData(this._allPoints, this._allArcs)

      if (this._heatmapManager?.active) {
        this._globe.heatmapsData([this._heatmapManager.baseData])
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
          .ringsData([])
        if (this._globe) this._packetAnimator?.update()
      }
    } catch (err) {
      if (err.name === 'AbortError') return
      console.error("[VERITAS Globe] Failed to load globe data:", err)
    }
  }

  // -------------------------------------------------------
  // Event Handlers (delegated from GlobeEventBus)
  // -------------------------------------------------------

  _onFlyToEvent(event) {
    const { lat, lng, articleId } = event.detail
    this._camera.flyTo(lat, lng)
    if (articleId) {
      this._interactions._setActiveCard(articleId)
      this._interactions.highlightArcForArticle(articleId)
    }
  }

  _onPerspectiveChange(event) {
    this._currentPerspective = event.detail.slug || event.detail.perspectiveId || "all"
    localStorage.setItem("veritas:perspective", this._currentPerspective)
    if (this._journeyActive) return
    if (this._globe && this._allPoints) {
      this._globe
        .hexBinPointsData([...this._allPoints])
        .arcsData([...this._allArcs || []])
    }
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

    // Client-side temporal filtering when we already have data
    if (this._temporalFilter.hasData && this._currentTimestamp) {
      const filtered = this._temporalFilter.filterByTime(this._currentTimestamp)
      if (filtered && this._globe) {
        this._globe
          .hexBinPointsData(filtered.points)
          .arcsData(filtered.arcs)

        // Pulse rings for newly appeared points
        if (filtered.newPointIds.size > 0) {
          const newRings = filtered.points
            .filter(p => filtered.newPointIds.has(p.id) && p.lat && p.lng)
            .slice(0, 5) // cap to prevent ring spam
            .map(p => ({
              lat: p.lat, lng: p.lng,
              maxRadius: 3, propagationSpeed: 2, repeatPeriod: 0,
              color: '#00f0ff', threat: 1
            }))
          if (newRings.length > 0) {
            this._globe.ringsData(newRings)
            setTimeout(() => { if (this._globe) this._globe.ringsData([]) }, 2000)
          }
        }

        this._packetAnimator?.update()
        return
      }
    }

    // LIVE mode or no cached data — refetch from server
    if (!this._currentTimestamp) {
      this._temporalFilter.setData([], []) // clear filter cache
    }
    this._loadData()
  }

  _onSearchEvent(event) {
    if (this._journeyActive) return
    const { query } = event.detail
    if (!query) { this._loadData(); return }
    this._networkView.search(query)
  }

  _onSearchClearEvent() {
    if (this._journeyActive) return
    this._currentSearchQuery = null
    this._networkView.returnToGlobal()
  }

  _onBreakingAlert(event) {
    const { lat, lng, severity, color } = event.detail
    if (!lat || !lng) return
    this._camera.flyTo(lat, lng, 1.1)
    this._broadcast.addSurgeRing(lat, lng, severity, color)
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

  _onHeatmapToggle() {
    if (this._journeyActive) return
    this._heatmapManager.toggle(() => this._loadData(), this._packetAnimator?.group)
  }

  _onDayNightToggle() {
    this._lighting.toggle()
  }

  _onModeChanged() {
    if (this._journeyActive) return
    this._loadData()
  }

  _onIsolateToggle() {
    if (this._journeyActive) return
    this._hideIsolated = !this._hideIsolated

    if (this._globe && !this._heatmapManager?.active) {
      const allPoints = this._allPoints || []
      const allArcs = this._allArcs || []

      if (this._hideIsolated) {
        const connectedIds = new Set()
        allArcs.forEach(arc => { if (arc.articleId) connectedIds.add(arc.articleId) })
        this._globe.hexBinPointsData(allPoints.filter(p => connectedIds.has(p.id)))
      } else {
        this._globe.hexBinPointsData(allPoints)
      }
    }

    window.dispatchEvent(new CustomEvent("veritas:isolateState", {
      detail: { active: this._hideIsolated }
    }))
  }

  _onJourneyActivated(event) {
    if (!this._globe) return
    if (this._timelapseEngine?.active) this._timelapseEngine._exitImmediate()
    this._journeyActive = true
    this._preJourneyState = event.detail?.state || this._preJourneyState || this.captureJourneyState()
    this._routeChoiceMenu.hide()
    if (this._packetAnimator?.group) this._packetAnimator.group.visible = false
    this._globe.arcsData([]).hexBinPointsData([]).ringsData([])
  }

  _onJourneyEnded(event) {
    this._journeyActive = false
    this._routeChoiceMenu.hide()
    this.restoreJourneyState(event.detail?.state || this._preJourneyState)
    this._preJourneyState = null
  }

  _onTimelapseToggle() {
    this._timelapseEngine.toggle()
  }

  _onBackToGlobal() {
    this._networkView?.returnToGlobal()
  }

  _onExploreArticle(e) {
    this._networkView?.loadArticleNetwork(e.detail?.articleId)
  }

  // -------------------------------------------------------
  // Journey
  // -------------------------------------------------------

  _startJourneyFromRoute(route, mode) {
    this._routeChoiceMenu.hide()
    window.dispatchEvent(new CustomEvent("veritas:startJourney", {
      detail: {
        mode,
        routeId: route.routeId || route.id,
        route,
        segments: route.segments || []
      }
    }))
  }

  _handleRouteMenuDocumentClick(event) {
    if (this._routeChoiceMenu.handleDocumentClick(event)) {
      this._interactions.clearArcSelection()
    }
  }

  // -------------------------------------------------------
  // Utilities
  // -------------------------------------------------------

  _cloneLayer(layer) {
    return JSON.parse(JSON.stringify(layer))
  }
}
