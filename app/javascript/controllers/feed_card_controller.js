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

    // Brief visual feedback: highlight the card before triggering globe action
    this.element.style.transition = 'box-shadow 0.15s ease, border-color 0.15s ease'
    this.element.style.boxShadow = '0 0 12px rgba(0,240,255,0.3)'
    this.element.style.borderColor = 'rgba(0,240,255,0.4)'
    setTimeout(() => {
      this.element.style.boxShadow = ''
      this.element.style.borderColor = ''
    }, 600)

    const route = this.journeyValue

    // Small delay so the glow registers before the globe takes focus
    setTimeout(() => {
      window.dispatchEvent(new CustomEvent("veritas:startJourney", {
        detail: {
          mode,
          routeId: route.routeId || route.id,
          route,
          segments: route.segments || []
        }
      }))
    }, 80)
  }
}
