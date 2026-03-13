import { Controller } from "@hotwired/stimulus"

const STORAGE_KEY = "veritas:perspective"

export default class extends Controller {
  static targets = ["pill"]

  connect() {
    const saved = localStorage.getItem(STORAGE_KEY) || "all"
    this._activate(saved)
  }

  select(event) {
    const id = event.currentTarget.dataset.perspectiveId
    if (!id) return
    this._activate(id)
    localStorage.setItem(STORAGE_KEY, id)
    window.dispatchEvent(new CustomEvent("veritas:perspectiveChange", {
      detail: { perspectiveId: id }
    }))
  }

  _activate(perspectiveId) {
    this.pillTargets.forEach(pill => {
      pill.classList.toggle("is-active", pill.dataset.perspectiveId === perspectiveId)
    })
  }
}
