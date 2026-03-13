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
    this._flyToHandler       = (e) => this._onFlyToEvent(e)
    this._perspectiveHandler = (e) => this._onPerspectiveChange(e)
    this._timelineHandler    = (e) => this._onTimelineChange(e)
    window.addEventListener("veritas:flyTo",             this._flyToHandler)
    window.addEventListener("veritas:perspectiveChange", this._perspectiveHandler)
    window.addEventListener("veritas:timelineChange",    this._timelineHandler)
    this._initGlobe()
    this._subscription = consumer.subscriptions.create("GlobeChannel", {
      received:     (data) => this._onBroadcast(data),
      rejected:     ()     => console.error("[VERITAS Globe] WebSocket subscription rejected")
    })
  }

  disconnect() {
    this._subscription?.unsubscribe()
    window.removeEventListener("veritas:flyTo",             this._flyToHandler)
    window.removeEventListener("veritas:perspectiveChange", this._perspectiveHandler)
    window.removeEventListener("veritas:timelineChange",    this._timelineHandler)
    clearTimeout(this._rotateTimer)
    if (this._resizeObserver) this._resizeObserver.disconnect()
    if (this._globe) {
      cancelAnimationFrame(this._animFrame)
      this._globe._destructor && this._globe._destructor()
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
      .onPointClick(point => this._onPointClicked(point))
      // Arcs layer (narrative arcs)
      .arcColor("color")
      .arcDashLength(0.4)
      .arcDashGap(0.2)
      .arcDashAnimateTime(1500)
      .arcStroke(0.5)
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
      .arcLabel(d => `
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
          <div style="color:#00f0ff;font-size:9px;letter-spacing:0.1em;margin-bottom:4px;">NARRATIVE ARC</div>
          <div>${d.originCountry} → ${d.targetCountry}</div>
        </div>
      `)
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
    } catch (err) {
      console.error("[VERITAS Globe] Failed to load globe data:", err)
    }
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

  _onArcClicked(arc) {
    if (!arc) return
    const midLat = (arc.startLat + arc.endLat) / 2
    const midLng = (arc.startLng + arc.endLng) / 2
    this._flyTo(midLat, midLng, 2.0)
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
    this._rotateTimer = setTimeout(() => { controls.autoRotate = true }, 6000)
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
}
