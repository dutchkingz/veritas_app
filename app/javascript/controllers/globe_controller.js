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
    this._currentPerspective = localStorage.getItem("veritas:perspective") || "all"
    this._currentTimestamp   = null
    this._pointHovered       = false
    this._arcHovered         = false
    this._flyToHandler       = (e) => this._onFlyToEvent(e)
    this._perspectiveHandler = (e) => this._onPerspectiveChange(e)
    this._timelineHandler    = (e) => this._onTimelineChange(e)
    this._searchHandler      = (e) => this._onSearchEvent(e)
    this._searchClearHandler = (e) => this._onSearchClearEvent(e)
    window.addEventListener("veritas:flyTo",             this._flyToHandler)
    window.addEventListener("veritas:perspectiveChange", this._perspectiveHandler)
    window.addEventListener("veritas:timelineChange",    this._timelineHandler)
    window.addEventListener("veritas:search",            this._searchHandler)
    window.addEventListener("veritas:searchClear",       this._searchClearHandler)
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
    this._subscription?.unsubscribe()
    window.removeEventListener("veritas:flyTo",             this._flyToHandler)
    window.removeEventListener("veritas:perspectiveChange", this._perspectiveHandler)
    window.removeEventListener("veritas:timelineChange",    this._timelineHandler)
    window.removeEventListener("veritas:search",            this._searchHandler)
    window.removeEventListener("veritas:searchClear",       this._searchClearHandler)
    clearTimeout(this._rotateTimer)
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
  }

  // -------------------------------------------------------
  // Private
  // -------------------------------------------------------

  async _initGlobe() {
    const Globe = (await import("globe.gl")).default

    const container = this.element

    this._globe = Globe()
      .globeImageUrl("//unpkg.com/three-globe/example/img/earth-night.jpg")
      .bumpImageUrl("//unpkg.com/three-globe/example/img/earth-topology.png")
      .backgroundImageUrl("//unpkg.com/three-globe/example/img/night-sky.png")
      .width(container.clientWidth)
      .height(container.clientHeight)
      .atmosphereColor("#00f0ff")
      .atmosphereAltitude(0.25)
      // Points layer (articles)
      .pointAltitude("size")
      .pointColor("color")
      .pointRadius(0.35)
      // NOTE: pointsMerge disabled — required for individual point click events
      .onPointHover(point => this._onPointHover(point))
      .onPointClick(point => this._onPointClicked(point))
      // Arcs layer (narrative arcs)
      .arcColor("color")
      .arcDashLength(0)  // Solid lines instead of dashed
      .arcDashGap(0)
      .arcDashAnimateTime(0)
      .arcStroke(d => d.thickness || 0.5)
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
        </div>
      `})
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
  }

  async _loadData() {
    try {
      const params = new URLSearchParams()
      if (this._currentPerspective && this._currentPerspective !== "all") {
        params.set("perspective_id", this._currentPerspective)
      }
      if (this._currentTimestamp) {
        params.set("to", this._currentTimestamp)
      }
      // ARCWEAVER 2.0: Load multi‑segment routes instead of simple arcs
      params.set("view", "segments")
      
      const query = params.toString()
      const url   = query ? `${this.dataUrlValue}?${query}` : this.dataUrlValue
      const response = await fetch(url)
      const data     = await response.json()

      const rings = (data.regions || []).map(r => ({
        ...r,
        ...(THREAT_RING[parseInt(r.threat, 10)] || THREAT_RING[1])
      }))

      this._globe
        .pointsData(data.points)
        .arcsData(data.arcs)
        .ringsData(rings)

      // Update packet animation with new arcs
      if (this._globe) {
        this._updatePackets()
      }
    } catch (err) {
      console.error("[VERITAS Globe] Failed to load globe data:", err)
    }
  }

  _updatePackets() {
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
      const material = new window.THREE.MeshBasicMaterial({
        color: segment.color || '#00f0ff',
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
    this._currentPerspective = event.detail.perspectiveId
    this._loadData()
  }

  _onTimelineChange(event) {
    this._currentTimestamp = event.detail.toTimestamp
    this._loadData()
  }

  _onPointClicked(point) {
    if (!point) return
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
    const midLat = (arc.startLat + arc.endLat) / 2
    const midLng = (arc.startLng + arc.endLng) / 2
    this._flyTo(midLat, midLng, 2.0)
    if (arc.articleId) this._setActiveCard(arc.articleId)
    
    // Show hop details in timeline sidebar
    this._showHopDetails(arc)
  }

  _onArcHover(arc) {
    // Reset previous hover highlights
    if (this._lastHoveredArc && this._lastHoveredArc !== arc && this._packets) {
      this._packets.forEach(packet => {
        if (packet.segment === this._lastHoveredArc) {
          packet.mesh.material.color.set(packet.segment.color || '#00f0ff')
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

 _onBroadcast(data) {
    if (!this._globe) return

    if (data.type === "new_point") {
      const current = this._globe.pointsData()
      this._globe.pointsData([...current, data.point])
    } else if (data.type === "update_point") {
      const current = this._globe.pointsData()
      this._globe.pointsData(
        current.map(p => p.id === data.point.id ? { ...p, ...data.point } : p)
      )
    }
  }

  // Handle search event from search_controller.js
  async _onSearchEvent(event) {
    const { query } = event.detail
    
    if (!query) {
      this._loadData() // Reset to default
      return
    }
    
    // Fetch filtered globe data based on search query
    try {
      const params = new URLSearchParams({
        search_query: query,
        view: 'segments'
      })
      
      if (this._currentPerspective && this._currentPerspective !== "all") {
        params.set("perspective_id", this._currentPerspective)
      }
      
      const url = `${this.dataUrlValue}?${params.toString()}`
      const response = await fetch(url)
      const data = await response.json()
      
      // Update globe with filtered data
      const rings = (data.regions || []).map(r => ({
        ...r,
        ...(THREAT_RING[parseInt(r.threat, 10)] || THREAT_RING[1])
      }))
      
      this._globe
        .pointsData(data.points || [])
        .arcsData(data.arcs || [])
        .ringsData(rings)
      
      // Update packet animation with new arcs
      if (this._globe) {
        this._updatePackets()
      }
      
      // Fly to first result if available
      if (data.arcs && data.arcs.length > 0) {
        const firstArc = data.arcs[0]
        const midLat = (firstArc.startLat + firstArc.endLat) / 2
        const midLng = (firstArc.startLng + firstArc.endLng) / 2
        this._flyTo(midLat, midLng, 2.0)
      }
      
      console.log(`[GlobeController] Search filter applied: "${query}" — ${data.arcs?.length || 0} arcs loaded`)
    } catch (err) {
      console.error('[GlobeController] Search filter failed:', err)
      this._loadData() // Fallback to default
    }
  }

  // Clear search filter and reset globe
  _onSearchClearEvent() {
    this._currentSearchQuery = null
    this._loadData() // Reset to default data
    console.log('[GlobeController] Search filter cleared')
  }
}
