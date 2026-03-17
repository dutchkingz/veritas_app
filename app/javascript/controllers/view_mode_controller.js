import { Controller } from "@hotwired/stimulus"

// ViewModeController
//
// Toggles body.glass-mode on/off and persists the preference in localStorage.
// Drop this controller on the toggle button itself.

const STORAGE_KEY = "veritas_view_mode"

export default class extends Controller {
  static targets = ["label", "icon"]

  connect() {
    if (localStorage.getItem(STORAGE_KEY) === "glass") {
      this._enable()
    }
  }

  toggle() {
    if (document.body.classList.contains("glass-mode")) {
      this._disable()
    } else {
      this._enable()
    }
  }

  _enable() {
    document.body.classList.add("glass-mode")
    localStorage.setItem(STORAGE_KEY, "glass")
    this.element.classList.add("is-active")
    if (this.hasLabelTarget) this.labelTarget.textContent = "GLASS"
  }

  _disable() {
    document.body.classList.remove("glass-mode")
    localStorage.setItem(STORAGE_KEY, "solid")
    this.element.classList.remove("is-active")
    if (this.hasLabelTarget) this.labelTarget.textContent = "SOLID"
  }
}
