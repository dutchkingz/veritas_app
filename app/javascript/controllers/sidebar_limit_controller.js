import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.limit = 20
    this._observer = new MutationObserver(() => this.enforceLimit())
    this._observer.observe(this.element, { childList: true })
    this.enforceLimit()
  }

  disconnect() {
    this._observer.disconnect()
  }

  enforceLimit() {
    const cards = this.element.querySelectorAll('.veritas-feed-card')
    if (cards.length > this.limit) {
      for (let i = this.limit; i < cards.length; i++) {
        cards[i].remove()
      }
    }
  }
}
