// Hex Layer — hex-bin weight, color, tooltip, and interaction helpers.

const THREAT_LEVELS = {
  SEVERE: 3, CRITICAL: 3, HIGH: 2, MODERATE: 1
}

export class HexLayer {
  constructor(controller) {
    this._c = controller
  }

  weight(d) {
    const threat = (d.threat_level || '').toUpperCase()
    return THREAT_LEVELS[threat] || 1
  }

  color(bin, face) {
    const points = bin.points || []
    let maxThreat = 0
    points.forEach(p => {
      const threat = (p.threat_level || '').toUpperCase()
      const level = THREAT_LEVELS[threat] || 0
      if (level > maxThreat) maxThreat = level
    })

    const alpha = face === 'top' ? 0.9 : 0.7
    if (maxThreat >= 3) return `rgba(255, 40, 40, ${alpha})`
    if (maxThreat >= 2) return `rgba(255, 140, 0, ${alpha})`
    if (maxThreat >= 1) return `rgba(255, 210, 0, ${alpha})`
    return `rgba(0, 255, 204, ${alpha})`
  }

  buildTooltip(bin) {
    if (!bin) return ''
    const points = bin.points || []
    const count = points.length
    if (count === 0) return ''

    let maxThreat = 0
    let maxThreatLabel = 'NORMAL'
    points.forEach(p => {
      const threat = (p.threat_level || '').toUpperCase()
      if ((threat === 'SEVERE' || threat === 'CRITICAL') && maxThreat < 3) { maxThreat = 3; maxThreatLabel = threat }
      else if (threat === 'HIGH' && maxThreat < 2) { maxThreat = 2; maxThreatLabel = 'HIGH' }
      else if (threat === 'MODERATE' && maxThreat < 1) { maxThreat = 1; maxThreatLabel = 'MODERATE' }
    })
    const threatColor = maxThreat >= 3 ? '#ff2828' : maxThreat >= 2 ? '#ff8c00' : maxThreat >= 1 ? '#ffd200' : '#00ffcc'

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

  onHover(hex) {
    this._c._camera.pointHovered = Boolean(hex)
  }

  onClicked(hex) {
    if (!hex || !this._c._globe) return
    if (this._c._journeyActive) return
    const center = hex.center || {}
    if (center.lat != null && center.lng != null) {
      this._c._camera.flyTo(center.lat, center.lng, 2.0)
    }
  }
}
