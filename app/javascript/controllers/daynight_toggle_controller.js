import { Controller } from "@hotwired/stimulus"

// Toggles day/night globe texture and lighting.
// Dispatches veritas:dayNightToggle and listens for veritas:dayNightState to sync UI.
export default class extends Controller {
  static targets = ["label"]

  connect() {
    this._stateHandler = (e) => this._onState(e)
    window.addEventListener("veritas:dayNightState", this._stateHandler)
    this._isDay = true
  }

  disconnect() {
    window.removeEventListener("veritas:dayNightState", this._stateHandler)
  }

  toggle() {
    window.dispatchEvent(new CustomEvent("veritas:dayNightToggle"))
  }

  _onState(event) {
    this._isDay = event.detail.isDay
    const label = this.hasLabelTarget ? this.labelTarget : null

    if (this._isDay) {
      this.element.classList.remove("is-active")
      if (label) label.textContent = "DAY"
    } else {
      this.element.classList.add("is-active")
      if (label) label.textContent = "NIGHT"
    }
  }
}
