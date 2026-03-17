import { Controller } from "@hotwired/stimulus"

// Toggles the threat heatmap thermal layer on the globe.
// Dispatches veritas:heatmapToggle and listens for veritas:heatmapState to sync UI.
export default class extends Controller {
  static targets = ["label", "btn"]

  connect() {
    this._stateHandler = (e) => this._onState(e)
    window.addEventListener("veritas:heatmapState", this._stateHandler)
    this._active = false
  }

  disconnect() {
    window.removeEventListener("veritas:heatmapState", this._stateHandler)
  }

  toggle() {
    window.dispatchEvent(new CustomEvent("veritas:heatmapToggle"))
  }

  _onState(event) {
    this._active = event.detail.active
    const btn   = this.hasBtnTarget ? this.btnTarget : this.element
    const label = this.hasLabelTarget ? this.labelTarget : null

    if (this._active) {
      btn.classList.add("is-active")
      if (label) label.textContent = "THERMAL ON"
    } else {
      btn.classList.remove("is-active")
      if (label) label.textContent = "THERMAL"
    }
  }
}
