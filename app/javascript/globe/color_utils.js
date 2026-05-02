// Pure color utility functions extracted from globe_controller.js
// No globe or DOM dependencies — stateless transforms only.

export function getDriftTargetColor(framing, intensity) {
  const alpha = 0.5 + (intensity * 0.3)
  switch (framing) {
    case 'distorted':
      return { r: Math.round(255), g: Math.round(60 - intensity * 30), b: Math.round(60 - intensity * 30), a: alpha }
    case 'amplified':
      return { r: 255, g: Math.round(160 - intensity * 100), b: Math.round(40 + intensity * 60), a: alpha }
    case 'neutralized':
      return { r: Math.round(80 + intensity * 40), g: Math.round(160 + intensity * 40), b: Math.round(220), a: alpha }
    case 'original':
    default:
      return { r: 0, g: 200, b: 255, a: 0.4 + intensity * 0.2 }
  }
}

export function getFramingColor(framing) {
  switch (framing) {
    case 'distorted':   return '#ff2d2d'
    case 'amplified':   return '#ff8c00'
    case 'neutralized': return '#6ea8d7'
    case 'original':    return '#00ffcc'
    default:            return '#607080'
  }
}

export function parseColor(colorStr) {
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

export function interpolateColor(c1, c2, t) {
  const r = Math.round(c1.r + (c2.r - c1.r) * t)
  const g = Math.round(c1.g + (c2.g - c1.g) * t)
  const b = Math.round(c1.b + (c2.b - c1.b) * t)
  const a = (c1.a + (c2.a - c1.a) * t).toFixed(2)
  return `rgba(${r},${g},${b},${a})`
}

export function buildGradientStops(sourceColor, targetColor, alpha) {
  const src = parseColor(sourceColor)
  const tgt = typeof targetColor === 'object' ? targetColor : parseColor(targetColor)
  if (alpha != null) { src.a = alpha; tgt.a = alpha }
  const stops = 8
  const colors = []
  for (let i = 0; i < stops; i++) {
    const t = i / (stops - 1)
    const eased = t * t
    colors.push(interpolateColor(src, tgt, eased))
  }
  return colors
}

export function hexToRgba(hex, alpha) {
  const h = hex.replace('#', '')
  if (h.length !== 6) return hex
  const r = parseInt(h.slice(0, 2), 16)
  const g = parseInt(h.slice(2, 4), 16)
  const b = parseInt(h.slice(4, 6), 16)
  return `rgba(${r},${g},${b},${alpha})`
}

export function dominantConnectionType(d) {
  const types = d.connectionTypes || []
  if (types.length === 0) return null
  if (types.length === 1) return types[0]
  const priority = ['narrative_route', 'gdelt_event', 'embedding_similarity', 'shared_entities']
  for (const p of priority) {
    if (types.includes(p)) return p
  }
  return types[0]
}

export function connectionTypeBadge(type) {
  const badges = {
    narrative_route:      { label: 'ROUTE',    color: '#a855f7' },
    gdelt_event:          { label: 'GDELT',    color: '#ef4444' },
    embedding_similarity: { label: 'SEMANTIC',  color: '#3b82f6' },
    shared_entities:      { label: 'ENTITIES',  color: '#22c55e' }
  }
  const b = badges[type] || { label: type.toUpperCase(), color: '#6b7280' }
  return `<span style="font-size:7px;padding:2px 5px;border-radius:3px;background:${b.color}20;color:${b.color};border:1px solid ${b.color}40;letter-spacing:0.5px;">${b.label}</span>`
}

export function isValidPoint(p) {
  if (p.lat == null || p.lng == null) return false
  if (Math.abs(p.lat) > 90 || Math.abs(p.lng) > 180) return false
  if (Math.abs(p.lat) < 1 && Math.abs(p.lng) < 1) return false
  return true
}

export function isValidArc(arc) {
  const { startLat, startLng, endLat, endLng } = arc
  if (startLat == null || startLng == null || endLat == null || endLng == null) return false
  if (Math.abs(startLat) > 90 || Math.abs(endLat) > 90) return false
  if (Math.abs(startLng) > 180 || Math.abs(endLng) > 180) return false
  if (Math.abs(startLat) < 1 && Math.abs(startLng) < 1) return false
  if (Math.abs(endLat) < 1 && Math.abs(endLng) < 1) return false
  if (Math.abs(startLat - endLat) < 2 && Math.abs(startLng - endLng) < 2) return false
  return true
}
