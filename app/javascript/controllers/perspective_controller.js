import { Controller } from "@hotwired/stimulus"

const STORAGE_KEY = "veritas:perspective"

export default class extends Controller {
  static targets = ["pill"]

  connect() {
    const saved = localStorage.getItem(STORAGE_KEY) || "all"
    this._currentSlug = saved
    this._activate(saved)
  }

  select(event) {
    const slug = event.currentTarget.dataset.perspectiveSlug
    if (!slug) return

    // Toggle off if same lens clicked again
    const next = this._currentSlug === slug ? "all" : slug
    this._currentSlug = next
    localStorage.setItem(STORAGE_KEY, next)
    this._activate(next)

    window.dispatchEvent(new CustomEvent("veritas:perspectiveChange", {
      detail: { slug: next }
    }))
  }

  _activate(slug) {
    this.pillTargets.forEach(pill => {
      pill.classList.toggle("is-active", pill.dataset.perspectiveSlug === slug)
    })
  }
}
