// Network View — article network, global network, search, and arc merging.
// Receives the globe controller instance for access to shared state.

import { isValidPoint, isValidArc } from "globe/color_utils"

export class NetworkView {
  constructor(controller) {
    this._c = controller
  }

  get _globe() { return this._c._globe }

  async search(query) {
    const c = this._c
    c._currentSearchQuery = query
    c._globeMode = "search"

    if (this._globe) {
      this._globe.arcsData([]).hexBinPointsData([]).ringsData([])
      if (c._packetAnimator?.group) c._packetAnimator.group.visible = false
    }

    c._abortController?.abort()
    c._abortController = new AbortController()
    const signal = c._abortController.signal

    try {
      const params = new URLSearchParams({ search_query: query, view: 'segments' })
      if (c._currentTopic) params.set("topic", c._currentTopic)

      const globeUrl = `${c.dataUrlValue}?${params.toString()}`
      const networkUrl = `/api/article_network/search?search_query=${encodeURIComponent(query)}`

      const [globeResponse, networkResponse] = await Promise.all([
        fetch(globeUrl, { signal }),
        fetch(networkUrl, { signal }).catch(() => null)
      ])

      const data = await globeResponse.json()
      let networkData = null
      if (networkResponse?.ok) {
        networkData = await networkResponse.json()
      }

      c._heatmapManager.baseData = data.heatmap || []
      c._heatmapManager.clusters = data.heatmapClusters || []
      c._allPoints = (data.points || []).filter(p => isValidPoint(p))

      const legacyArcs = (data.arcs || []).filter(a => isValidArc(a))
      const networkArcs = (networkData?.arcs || []).filter(a => isValidArc(a))
      c._allArcs = networkArcs.length > 0
        ? this.mergeArcSets(networkArcs, legacyArcs)
        : legacyArcs

      if (c._heatmapManager?.active) {
        this._globe.heatmapsData([c._heatmapManager.baseData])
      } else {
        let visiblePoints = c._allPoints
        if (c._hideIsolated) {
          const connectedIds = new Set()
          c._allArcs.forEach(arc => {
            if (arc.articleId) connectedIds.add(arc.articleId)
            if (arc.sourceArticleId) connectedIds.add(arc.sourceArticleId)
            if (arc.targetArticleId) connectedIds.add(arc.targetArticleId)
          })
          visiblePoints = c._allPoints.filter(p => connectedIds.has(p.id))
        }

        this._globe
          .hexBinPointsData(visiblePoints)
          .arcsData(c._allArcs)
          .ringsData([])

        if (c._packetAnimator?.group) c._packetAnimator.group.visible = true
        c._packetAnimator?.update()
      }

      const primaryArc = c._allArcs.find(a => a.connectionTypes) || c._allArcs.find(a => a.tier === 1) || c._allArcs[0]
      if (primaryArc) {
        const midLat = (primaryArc.startLat + primaryArc.endLat) / 2
        const midLng = (primaryArc.startLng + primaryArc.endLng) / 2
        c._camera.flyTo(midLat, midLng, 2.0)
      }

      console.log(`[VERITAS Globe] Search: "${query}" — ${networkArcs.length} network + ${legacyArcs.length} legacy = ${c._allArcs.length} arcs`)
    } catch (err) {
      if (err.name === 'AbortError') return
      console.error('[VERITAS Globe] Search filter failed:', err)
      c._loadData()
    }
  }

  async loadArticleNetwork(articleId) {
    if (!articleId) return
    const c = this._c
    c._globeMode = "network"
    c._networkCenterArticleId = articleId

    c._abortController?.abort()
    c._abortController = new AbortController()
    const signal = c._abortController.signal

    if (this._globe) {
      this._globe.arcsData([]).ringsData([])
      if (c._packetAnimator?.group) c._packetAnimator.group.visible = false
    }

    try {
      const url = `/api/article_network/${articleId}?depth=2&time_window=48`
      const response = await fetch(url, { signal })
      const data = await response.json()

      c._networkData = data
      this.renderNetworkData(data, articleId)

      window.dispatchEvent(new CustomEvent("veritas:networkLoaded", {
        detail: { articleId, data, mode: "network" }
      }))

      this.showBackToGlobalButton(true)

      console.log(`[VERITAS Globe] Network View: Article #${articleId} — ${data.arcs?.length || 0} connections, ${data.articles?.length || 0} nodes`)
    } catch (err) {
      if (err.name === 'AbortError') return
      console.error('[VERITAS Globe] Network view failed:', err)
      this.returnToGlobal()
    }
  }

  async loadGlobalNetwork() {
    const c = this._c
    c._globeMode = "global"
    c._networkCenterArticleId = null

    c._abortController?.abort()
    c._abortController = new AbortController()
    const signal = c._abortController.signal

    try {
      const networkUrl = `/api/article_network/global`
      const response = await fetch(networkUrl, { signal })
      const networkData = await response.json()

      const params = new URLSearchParams({ view: "segments" })
      if (c._currentTopic) params.set("topic", c._currentTopic)
      if (c._currentTimestamp) params.set("to", c._currentTimestamp)
      const globeUrl = `${c.dataUrlValue}?${params.toString()}`
      const globeResponse = await fetch(globeUrl, { signal })
      const globeData = await globeResponse.json()

      c._heatmapManager.baseData = globeData.heatmap || []
      c._heatmapManager.clusters = globeData.heatmapClusters || []
      c._allPoints = (globeData.points || []).filter(p => isValidPoint(p))

      const existingArcs = (globeData.arcs || []).filter(a => isValidArc(a))
      const networkArcs = (networkData.arcs || []).filter(a => isValidArc(a))
      const combinedArcs = this.mergeArcSets(networkArcs, existingArcs)

      c._allArcs = combinedArcs
      c._allRoutes = globeData.routes || []

      // Feed temporal filter for DVR replay
      if (c._temporalFilter) c._temporalFilter.setData(c._allPoints, c._allArcs)

      if (c._heatmapManager?.active) {
        this._globe.heatmapsData([c._heatmapManager.baseData])
      } else {
        let visiblePoints = c._allPoints
        if (c._hideIsolated) {
          const connectedIds = new Set()
          combinedArcs.forEach(arc => {
            if (arc.articleId) connectedIds.add(arc.articleId)
            if (arc.sourceArticleId) connectedIds.add(arc.sourceArticleId)
            if (arc.targetArticleId) connectedIds.add(arc.targetArticleId)
          })
          visiblePoints = c._allPoints.filter(p => connectedIds.has(p.id))
        }

        this._globe
          .hexBinPointsData(visiblePoints)
          .arcsData(combinedArcs)
          .ringsData([])

        if (c._packetAnimator?.group) c._packetAnimator.group.visible = true
        c._packetAnimator?.update()
      }

      this.showBackToGlobalButton(false)

      console.log(`[VERITAS Globe] Global Network View — ${networkArcs.length} network arcs + ${existingArcs.length} segment arcs`)
    } catch (err) {
      if (err.name === 'AbortError') return
      console.error('[VERITAS Globe] Global network view failed, falling back:', err)
      c._fetchAndRender()
    }
  }

  returnToGlobal() {
    const c = this._c
    c._globeMode = "global"
    c._networkCenterArticleId = null
    c._networkData = null
    this.showBackToGlobalButton(false)

    window.dispatchEvent(new CustomEvent("veritas:networkCleared"))

    this.loadGlobalNetwork()
  }

  renderNetworkData(data, centerArticleId) {
    const c = this._c
    if (!this._globe || !data) return

    const articles = data.articles || []
    const arcs = (data.arcs || []).filter(a => isValidArc(a))
    const renderArcs = arcs.slice(0, 60)

    const points = articles.filter(a => isValidPoint(a)).map(a => ({
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

    const center = articles.find(a => a.isCenter)
    if (center) c._camera.flyTo(center.lat, center.lng, 2.2)

    const rings = center ? [{ lat: center.lat, lng: center.lng, maxR: 3, propagationSpeed: 2, repeatPeriod: 1500 }] : []

    c._allPoints = points
    c._allArcs = renderArcs

    this._globe
      .hexBinPointsData(points)
      .arcsData(renderArcs)
      .ringsData(rings)

    if (c._packetAnimator?.group) c._packetAnimator.group.visible = true
    c._packetAnimator?.update()
  }

  mergeArcSets(primary, secondary) {
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

  showBackToGlobalButton(show) {
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
      btn.addEventListener('click', () => this.returnToGlobal())
      document.body.appendChild(btn)
    } else if (!show && btn) {
      btn.remove()
    }
  }
}
