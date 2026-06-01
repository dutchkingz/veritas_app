// Globe Interactions — click/hover handlers for points, arcs, and related UI.

import { showHopDetails } from "globe/hop_details_panel"

export class GlobeInteractions {
  constructor(controller) {
    this._c = controller
    this._lastHoveredArc = null
  }

  onPointClicked(point) {
    if (!point) return
    if (this._c._journeyActive) return
    this._c._camera.flyTo(point.lat, point.lng)
    if (point.id) this._setActiveCard(point.id)
    if (point.id) this._c._networkView.loadArticleNetwork(point.id)
  }

  onPointHover(point) {
    this._c._camera.pointHovered = Boolean(point)
  }

  onArcClicked(arc) {
    if (!arc) return
    if (this._c._journeyActive) return

    const midLat = (arc.startLat + arc.endLat) / 2
    const midLng = (arc.startLng + arc.endLng) / 2
    this._c._camera.flyTo(midLat, midLng, 2.0)

    // Network arcs: re-center on the other end of the connection
    if (arc.connectionTypes) {
      const targetId = arc.targetArticleId || arc.sourceArticleId
      if (targetId && targetId !== this._c._networkCenterArticleId) {
        this._c._networkView.loadArticleNetwork(targetId)
        return
      }
    }

    if (arc.articleId) this._setActiveCard(arc.articleId)

    // Show Bloom/Chronicle menu for any arc with a route
    if (arc.routeId) {
      this._c._routeChoiceMenu.show(arc, {
        getRoute: (id) => this._c.getRoute(id),
        getScreenPosition: (lat, lng) => this._c.getScreenPosition(lat, lng),
        onBloom: (route) => this._c._startJourneyFromRoute(route, "bloom"),
        onChronicle: (route) => this._c._startJourneyFromRoute(route, "chronicle"),
        onStory: (route) => { this._c._routeChoiceMenu.hide(); this._c._timelapseEngine.startStory(route.routeId || route.id) }
      })
    }

    showHopDetails(arc)

    // Highlight this arc visually
    this._c._selectedArcArticleId = arc.articleId
    this._c._globe.arcsData(this._c._globe.arcsData())

    // Open Narrative DNA panel
    if (arc.articleId) {
      window.dispatchEvent(new CustomEvent("veritas:openNarrativeDna", {
        detail: { articleId: arc.articleId }
      }))
    }
  }

  onArcHover(arc) {
    if (this._c._journeyActive) return

    // Reset previous hover highlights
    if (this._lastHoveredArc && this._lastHoveredArc !== arc && this._c._packetAnimator?.packets) {
      this._c._packetAnimator.packets.forEach(packet => {
        if (packet.segment === this._lastHoveredArc) {
          let packetColor = packet.segment.color || '#00f0ff'
          if (Array.isArray(packetColor)) packetColor = packetColor[0]
          packet.mesh.material.color.set(packetColor)
          packet.mesh.scale.set(1, 1, 1)
        }
      })
    }

    this._c._camera.arcHovered = Boolean(arc)

    // Highlight the segment on hover
    if (arc && this._c._packetAnimator?.packets) {
      this._c._packetAnimator.packets.forEach(packet => {
        if (packet.segment === arc) {
          packet.mesh.material.color.set('#ffffff')
          packet.mesh.scale.set(1.5, 1.5, 1.5)
        }
      })
    }

    this._lastHoveredArc = arc
  }

  highlightArcForArticle(articleId) {
    if (!this._c._globe) return

    const arcs = this._c._globe.arcsData() || []
    const arc = arcs.find(a => String(a.articleId) === String(articleId))
    if (!arc) return

    this._c._selectedArcArticleId = articleId
    this._c._globe.arcsData(arcs)

    const midLat = (arc.startLat + arc.endLat) / 2
    const midLng = (arc.startLng + arc.endLng) / 2
    this._c._camera.flyTo(midLat, midLng, 2.0)

    if (arc.routeId) {
      this._c._routeChoiceMenu.show(arc, {
        getRoute: (id) => this._c.getRoute(id),
        getScreenPosition: (lat, lng) => this._c.getScreenPosition(lat, lng),
        onBloom: (route) => this._c._startJourneyFromRoute(route, "bloom"),
        onChronicle: (route) => this._c._startJourneyFromRoute(route, "chronicle"),
        onStory: (route) => { this._c._routeChoiceMenu.hide(); this._c._timelapseEngine.startStory(route.routeId || route.id) }
      })
    }
  }

  clearArcSelection() {
    if (!this._c._selectedArcArticleId) return
    this._c._selectedArcArticleId = null
    if (this._c._globe) this._c._globe.arcsData(this._c._globe.arcsData())
  }

  _setActiveCard(articleId) {
    document.querySelectorAll('.veritas-feed-card').forEach(card => {
      card.classList.remove('is-active')
    })

    // Dispatch event to feed-mode controller to reveal the card if hidden
    window.dispatchEvent(new CustomEvent("veritas:revealArticle", {
      detail: { articleId: String(articleId) }
    }))

    // Small delay to let the feed-mode controller render before scrolling
    setTimeout(() => {
      const card = document.querySelector(`.veritas-feed-card[data-article-id="${articleId}"]`)
      if (card) {
        card.classList.add('is-active')
        card.scrollIntoView({ behavior: 'smooth', block: 'nearest' })
      }
    }, 50)
  }
}
