import { Controller } from "@hotwired/stimulus"

// ViewToggleController
//
// Pill toggle that appears on the globe when a search is active.
// Two states: "SEARCH" (show only search-filtered arcs) vs "ALL INTEL" (show everything).
// Listens for veritas:search-results to show itself.
// Listens for veritas:search-cleared to hide itself.
// Dispatches veritas:view-mode-changed → globe_controller re-fetches accordingly.

export default class extends Controller {
  static targets = ["searchBtn", "allBtn"]

  connect() {
    this._onSearchResults = () => this._activate("search")
    this._onSearchCleared = () => this._deactivate()

    window.addEventListener("veritas:search-results", this._onSearchResults)
    window.addEventListener("veritas:search-cleared",  this._onSearchCleared)
  }

  disconnect() {
    window.removeEventListener("veritas:search-results", this._onSearchResults)
    window.removeEventListener("veritas:search-cleared",  this._onSearchCleared)
  }

  setSearch() {
    this._setActive("search")
    window.dispatchEvent(new CustomEvent("veritas:view-mode-changed", {
      detail: { mode: "search" }
    }))
  }

  setAll() {
    this._setActive("all")
    window.dispatchEvent(new CustomEvent("veritas:view-mode-changed", {
      detail: { mode: "all" }
    }))
  }

  // ─── Private ───────────────────────────────────────────────────────────────

  _activate(mode) {
    this.element.classList.remove("d-none")
    this._setActive(mode)
  }

  _deactivate() {
    this.element.classList.add("d-none")
  }

  _setActive(mode) {
    const searchActive = mode === "search"

    if (this.hasSearchBtnTarget) {
      this.searchBtnTarget.style.background = searchActive ? "#00f0ff" : "transparent"
      this.searchBtnTarget.style.color      = searchActive ? "#0a0c14" : "#64748b"
    }
    if (this.hasAllBtnTarget) {
      this.allBtnTarget.style.background = searchActive ? "transparent" : "#00f0ff"
      this.allBtnTarget.style.color      = searchActive ? "#64748b"    : "#0a0c14"
    }
  }
}
