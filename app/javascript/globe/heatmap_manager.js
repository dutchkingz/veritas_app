// Heatmap (Threat Thermal Layer) — toggle, pulse, hover tooltips, flare.
// Receives the globe instance and manages its own UI state.

export class HeatmapManager {
  constructor(globe) {
    this._globe = globe
    this._active = false
    this._baseData = []
    this._clusters = []
    this._pulseId = null
    this._tooltipEl = null
    this._lastHoveredCluster = null
  }

  get active() { return this._active }
  set active(v) { this._active = v }
  get baseData() { return this._baseData }
  set baseData(v) { this._baseData = v }
  get clusters() { return this._clusters }
  set clusters(v) { this._clusters = v }

  toggle(loadDataFn, packetGroup) {
    this._active = !this._active

    if (this._active) {
      this._globe.arcsData([]).hexBinPointsData([]).ringsData([])
      if (packetGroup) packetGroup.visible = false

      loadDataFn().then(() => {
        this._pulseId = setInterval(() => this._pulse(), 2500)
      })
    } else {
      if (this._pulseId) {
        clearInterval(this._pulseId)
        this._pulseId = null
      }
      this._globe.heatmapsData([])
      this.hideTooltip()
      if (packetGroup) packetGroup.visible = true
      loadDataFn()
    }

    window.dispatchEvent(new CustomEvent("veritas:heatmapState", {
      detail: { active: this._active }
    }))
  }

  _pulse() {
    if (!this._globe || !this._active || !this._baseData.length) return

    const pulsed = this._baseData.map(p => ({
      lat:    p.lat,
      lng:    p.lng,
      weight: Math.min(1, p.weight * (0.92 + Math.random() * 0.16))
    }))

    this._globe.heatmapsData([pulsed])
  }

  handleHover(event, container) {
    if (!this._active || !this._globe || !this._clusters.length) return

    const rect = container.getBoundingClientRect()
    const mx = event.clientX - rect.left
    const my = event.clientY - rect.top

    let nearest = null
    let nearestDist = Infinity
    for (const cluster of this._clusters) {
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

    if (!nearest || nearestDist > 80) {
      this.hideTooltip()
      return
    }

    if (this._lastHoveredCluster === nearest) return
    this._lastHoveredCluster = nearest
    this._showTooltip(nearest)
  }

  _showTooltip(cluster) {
    if (!this._tooltipEl) {
      this._tooltipEl = document.createElement('div')
      this._tooltipEl.className = 'vt-heatmap-tooltip'
      document.querySelector('.veritas-globe-section')?.appendChild(this._tooltipEl)
    }

    const threatColor = cluster.avgThreat >= 7 ? '#ff3a5e'
      : cluster.avgThreat >= 4 ? '#ffc107'
      : cluster.avgThreat >= 1 ? '#00ff87' : '#64748b'

    const headlines = (cluster.topHeadlines || []).map(h =>
      `<div style="margin-bottom:4px;">
        <span style="color:${threatColor};font-size:8px;">\u25A0</span>
        <span style="color:#8b95a5;font-size:8px;margin-right:4px;">${h.source}</span>
        <span style="font-size:10px;">${h.headline}</span>
      </div>`
    ).join('')

    this._tooltipEl.innerHTML = `
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

    this._tooltipEl.classList.add('is-visible')
  }

  hideTooltip() {
    if (this._tooltipEl) {
      this._tooltipEl.classList.remove('is-visible')
    }
    this._lastHoveredCluster = null
  }

  flareAt(lat, lng) {
    if (!this._active) return

    const flare = { lat, lng, weight: 1.0 }
    this._baseData.push(flare)
    this._globe.heatmapsData([[...this._baseData]])

    setTimeout(() => {
      const idx = this._baseData.indexOf(flare)
      if (idx !== -1) this._baseData.splice(idx, 1)
    }, 2000)
  }

  dispose() {
    if (this._pulseId) {
      clearInterval(this._pulseId)
      this._pulseId = null
    }
    this.hideTooltip()
    if (this._tooltipEl) {
      this._tooltipEl.remove()
      this._tooltipEl = null
    }
  }
}
