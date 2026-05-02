// Route choice popup menu — BLOOM / CHRONICLE / STORY options on arc click.
// Pure DOM rendering, no globe dependency beyond screen position.

export class RouteChoiceMenu {
  constructor(containerEl) {
    this._containerEl = containerEl
    this._menuEl = null
    this._openedAt = null
  }

  show(arc, { getRoute, getScreenPosition, onBloom, onChronicle, onStory }) {
    const route = getRoute(arc.routeId)
    if (!route) return

    this.hide()

    const position = getScreenPosition(
      (arc.startLat + arc.endLat) / 2,
      (arc.startLng + arc.endLng) / 2
    )
    if (!position) return

    const menu = document.createElement("div")
    menu.className = "vt-route-choice-menu"
    menu.style.left = `${position.x}px`
    menu.style.top = `${position.y}px`
    menu.innerHTML = `
      <div class="vt-route-choice-header">${route.routeName || "Narrative Route"}</div>
      <button class="vt-route-choice-btn vt-route-choice-btn--bloom" type="button">\u25C9 BLOOM</button>
      <button class="vt-route-choice-btn vt-route-choice-btn--chronicle" type="button">\u25B6 CHRONICLE</button>
      <button class="vt-route-choice-btn vt-route-choice-btn--story" type="button">\u23F1 STORY</button>
    `

    const [bloomBtn, chronicleBtn, storyBtn] = menu.querySelectorAll("button")
    bloomBtn?.addEventListener("click", (e) => { e.stopPropagation(); onBloom(route) })
    chronicleBtn?.addEventListener("click", (e) => { e.stopPropagation(); onChronicle(route) })
    storyBtn?.addEventListener("click", (e) => { e.stopPropagation(); onStory(route) })

    this._containerEl.appendChild(menu)
    this._menuEl = menu
    this._openedAt = Date.now()
  }

  hide() {
    if (this._menuEl) this._menuEl.remove()
    this._menuEl = null
  }

  handleDocumentClick(event) {
    if (!this._menuEl) return false
    if (Date.now() - this._openedAt < 80) return false
    if (this._menuEl.contains(event.target)) return false
    this.hide()
    return true
  }
}
