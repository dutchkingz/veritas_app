// Temporal Filter — client-side time filtering for DVR replay mode.
// Receives the full dataset once, then filters by timestamp without re-fetching.

export class TemporalFilter {
  constructor() {
    this._points = []
    this._arcs = []
    this._lastTimestamp = null
    this._lastPointIds = new Set()
    this._lastArcIds = new Set()
  }

  // Load the full dataset (called once on data fetch)
  setData(points, arcs) {
    this._points = points || []
    this._arcs = arcs || []
    this._lastTimestamp = null
    this._lastPointIds = new Set()
    this._lastArcIds = new Set()
  }

  get hasData() {
    return this._points.length > 0 || this._arcs.length > 0
  }

  // Returns items visible at the given timestamp, plus "new since last frame" sets.
  // timestamp: unix seconds (same format as timeline controller)
  // Returns null if no timestamp (LIVE mode — show everything)
  filterByTime(timestamp) {
    if (!timestamp) {
      this._lastTimestamp = null
      this._lastPointIds = new Set()
      this._lastArcIds = new Set()
      return null // caller should show full dataset
    }

    const cutoff = timestamp * 1000 // convert to ms for Date comparison

    const visiblePoints = this._points.filter(p => {
      const t = p.publishedAt ? new Date(p.publishedAt).getTime() : 0
      return t <= cutoff
    })

    const visibleArcs = this._arcs.filter(a => {
      // Use the earliest available timestamp on the arc
      const t = _arcTimestamp(a)
      return t <= cutoff
    })

    const currentPointIds = new Set(visiblePoints.map(p => p.id))
    const currentArcIds = new Set(visibleArcs.map(a => a.id || `${a.sourceArticleId}-${a.targetArticleId}`))

    // Compute "new since last frame"
    const newPointIds = new Set()
    const newArcIds = new Set()

    if (this._lastTimestamp !== null) {
      currentPointIds.forEach(id => {
        if (!this._lastPointIds.has(id)) newPointIds.add(id)
      })
      currentArcIds.forEach(id => {
        if (!this._lastArcIds.has(id)) newArcIds.add(id)
      })
    }

    this._lastTimestamp = timestamp
    this._lastPointIds = currentPointIds
    this._lastArcIds = currentArcIds

    return { points: visiblePoints, arcs: visibleArcs, newPointIds, newArcIds }
  }

  // Get the time range of the loaded data (for playback bounds)
  getTimeRange() {
    let min = Infinity, max = -Infinity

    this._points.forEach(p => {
      if (p.publishedAt) {
        const t = new Date(p.publishedAt).getTime()
        if (t < min) min = t
        if (t > max) max = t
      }
    })

    this._arcs.forEach(a => {
      const t = _arcTimestamp(a)
      if (t > 0) {
        if (t < min) min = t
        if (t > max) max = t
      }
    })

    if (min === Infinity) return null
    return { min: Math.floor(min / 1000), max: Math.floor(max / 1000) }
  }
}

function _arcTimestamp(arc) {
  const raw = arc.sourcePublishedAt || arc.publishedAt || arc.startPublishedAt
  return raw ? new Date(raw).getTime() : 0
}
