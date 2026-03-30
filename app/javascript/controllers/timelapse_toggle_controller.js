import { Controller } from "@hotwired/stimulus"

// Toggles the Narrative Timelapse cinematic playback mode on the globe.
// Dispatches veritas:timelapseStart and listens for veritas:timelapseState to sync UI.
export default class extends Controller {
  static targets = ["label", "btn"]

  connect() {
    this._stateHandler = (e) => this._onState(e)
    window.addEventListener("veritas:timelapseState", this._stateHandler)
    this._active = false
  }

  disconnect() {
    window.removeEventListener("veritas:timelapseState", this._stateHandler)
  }

  toggle() {
    window.dispatchEvent(new CustomEvent("veritas:timelapseToggle"))
  }

  _onState(event) {
    this._active = event.detail.active
    const btn   = this.hasBtnTarget ? this.btnTarget : this.element
    const label = this.hasLabelTarget ? this.labelTarget : null

    if (this._active) {
      btn.classList.add("is-active")
      if (label) label.textContent = "TIMELAPSE ▶"
    } else {
      btn.classList.remove("is-active")
      if (label) label.textContent = "TIMELAPSE"
    }
  }
}
