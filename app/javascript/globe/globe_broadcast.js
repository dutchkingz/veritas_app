// Globe Broadcast — ActionCable subscription and real-time signal handling.

export class GlobeBroadcast {
  constructor(controller) {
    this._c = controller
    this._subscription = null
    this._refreshTimeout = null
  }

  subscribe(consumer) {
    this._subscription = consumer.subscriptions.create("GlobeChannel", {
      received: (data) => this._onBroadcast(data),
      rejected: () => console.error("[VERITAS Globe] WebSocket subscription rejected")
    })
  }

  unsubscribe() {
    this._subscription?.unsubscribe()
    if (this._refreshTimeout) clearTimeout(this._refreshTimeout)
  }

  _onBroadcast(data) {
    const globe = this._c._globe
    if (!globe) return
    if (this._c._journeyActive) return

    if (data.type === "new_point") {
      const current = globe.hexBinPointsData() || []
      globe.hexBinPointsData([...current, data.point])

      if (data.point.lat && data.point.lng) {
        this._onNewSignal(data.point)
        this._c._heatmapManager?.flareAt(data.point.lat, data.point.lng)
      }
    } else if (data.type === "update_point") {
      const current = globe.hexBinPointsData() || []
      globe.hexBinPointsData(
        current.map(p => p.id === data.point.id ? { ...p, ...data.point } : p)
      )
    } else if (data.type === "routes_updated" || data.type === "articles_fetched") {
      if (this._refreshTimeout) clearTimeout(this._refreshTimeout)
      this._refreshTimeout = setTimeout(() => this._c._loadData(), 2000)
    }
  }

  _onNewSignal(point) {
    const globe = this._c._globe
    if (!globe) return

    const ring = {
      lat: point.lat,
      lng: point.lng,
      maxRadius: 3,
      propagationSpeed: 2,
      repeatPeriod: 0,
      color: '#00f0ff',
      threat: 1
    }
    const currentRings = globe.ringsData() || []
    globe.ringsData([...currentRings, ring])
    setTimeout(() => {
      const updated = (globe.ringsData() || []).filter(r => r !== ring)
      globe.ringsData(updated)
    }, 2000)
  }

  addSurgeRing(lat, lng, severity, color) {
    const globe = this._c._globe
    if (!globe) return

    const ringColor = color || "#ff3a5e"
    const surgeRing = {
      lat, lng,
      color: ringColor,
      maxRadius: 12,
      propagationSpeed: 4.5,
      repeatPeriod: 600
    }

    const current = globe.ringsData() || []
    globe.ringsData([...current, surgeRing])

    setTimeout(() => {
      const updated = (globe.ringsData() || []).filter(r => r !== surgeRing)
      globe.ringsData(updated)
    }, 30000)
  }
}
