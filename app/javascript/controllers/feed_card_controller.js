import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    lat: Number,
    lng: Number,
    articleId: Number,
    journeyAvailable: Boolean,
    journey: Object
  }

  select() {
    window.dispatchEvent(new CustomEvent('veritas:flyTo', {
      detail: { lat: this.latValue, lng: this.lngValue, articleId: this.articleIdValue }
    }))
  }

  openArticle(event) {
    event.stopPropagation()
  }

  openBloom(event) {
    this._startJourney(event, "bloom")
  }

  openChronicle(event) {
    this._startJourney(event, "chronicle")
  }

  openDna(event) {
    event.stopPropagation()
    window.dispatchEvent(new CustomEvent("veritas:openNarrativeDna", {
      detail: { articleId: this.articleIdValue }
    }))
  }

  openTribunal(event) {
    event.stopPropagation()
    window.dispatchEvent(new CustomEvent("veritas:openTribunal", {
      detail: { articleId: this.articleIdValue }
    }))
  }

  openNexus(event) {
    event.stopPropagation()
    window.dispatchEvent(new CustomEvent("veritas:openEntityNexus", {
      detail: { articleId: this.articleIdValue }
    }))
  }

  _startJourney(event, mode) {
    event.stopPropagation()
    if (!this.journeyAvailableValue || !this.hasJourneyValue) return

    const route = this.journeyValue

    window.dispatchEvent(new CustomEvent("veritas:startJourney", {
      detail: {
        mode,
        routeId: route.routeId || route.id,
        route,
        segments: route.segments || []
      }
    }))
  }
}
