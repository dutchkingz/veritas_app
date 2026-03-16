import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { lat: Number, lng: Number, articleId: Number }

  select() {
    window.dispatchEvent(new CustomEvent('veritas:flyTo', {
      detail: { lat: this.latValue, lng: this.lngValue, articleId: this.articleIdValue }
    }))
  }

  openArticle(event) {
    event.stopPropagation()
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
}
