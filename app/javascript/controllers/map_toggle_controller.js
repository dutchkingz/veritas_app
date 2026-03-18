import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["globe", "flat", "btn", "label"]

  connect() {
    this._viewMode = localStorage.getItem("veritas_map_projection") || "globe"
    this._apply()
  }

  toggle() {
    this._viewMode = this._viewMode === "globe" ? "flat" : "globe"
    localStorage.setItem("veritas_map_projection", this._viewMode)
    this._apply()
    
    // Notify controllers that the view has changed
    window.dispatchEvent(new CustomEvent("veritas:mapProjectionChanged", {
      detail: { mode: this._viewMode }
    }))
  }

  _apply() {
    const isGlobe = this._viewMode === "globe"
    
    if (this.hasGlobeTarget) {
      this.globeTarget.classList.toggle("d-none", !isGlobe)
    }
    
    if (this.hasFlatTarget) {
      this.flatTarget.classList.toggle("d-none", isGlobe)
    }
    
    if (this.hasBtnTarget) {
      this.btnTarget.classList.toggle("is-active", !isGlobe)
    }
    
    if (this.hasLabelTarget) {
      this.labelTarget.textContent = isGlobe ? "FLAT MAP" : "3D GLOBE"
    }
    
    // Hide Globe-specific controls when Flat Map is active
    const heatmapBtn = document.querySelector('[data-controller="heatmap-toggle"]')
    const dayNightBtn = document.querySelector('[data-controller="daynight-toggle"]')
    
    if (heatmapBtn) heatmapBtn.style.display = isGlobe ? "" : "none"
    if (dayNightBtn) dayNightBtn.style.display = isGlobe ? "" : "none"
  }
}
