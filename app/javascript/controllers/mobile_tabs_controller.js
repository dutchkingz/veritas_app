import { Controller } from "@hotwired/stimulus"

const PANELS = {
  globe:  ".veritas-globe-section",
  feed:   ".veritas-feed-sidebar",
  threat: ".veritas-status-sidebar"
}

export default class extends Controller {
  static targets = ["tab"]

  connect() {
    this._showPanel("globe")
  }

  show(event) {
    const panel = event.currentTarget.dataset.panel
    this._showPanel(panel)
    this.tabTargets.forEach(t => t.classList.toggle("is-active", t.dataset.panel === panel))
  }

  _showPanel(active) {
    Object.entries(PANELS).forEach(([key, selector]) => {
      const el = document.querySelector(selector)
      if (el) el.classList.toggle("mobile-hidden", key !== active)
    })
  }
}
