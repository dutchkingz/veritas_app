import { Controller } from "@hotwired/stimulus"

const THREAT_LEVELS = [
  { key: "all",      label: "ALL SIGNALS",          color: "#00f0ff" },
  { key: "CRITICAL", label: "CRITICAL THREATS",     color: "#ff3a5e" },
  { key: "HIGH",     label: "HIGH-THREAT SIGNALS",  color: "#ff6b2b" },
  { key: "MODERATE", label: "MODERATE SIGNALS",     color: "#ffc107" },
  { key: "LOW",      label: "LOW-THREAT SIGNALS",   color: "#22c55e" },
  { key: "NEGLIGIBLE", label: "NEGLIGIBLE SIGNALS", color: "#6b7280" }
]

export default class extends Controller {
  static targets = ["btn", "list", "loadMore", "loadMoreWrap", "badge", "card", "threatLabel"]

  connect() {
    this.currentMode = "hot"
    this.visibleCount = 15
    this.perPage = 15
    this.threatIndex = 0  // 0 = "all"
    this._revealHandler = this._revealArticle.bind(this)
    window.addEventListener("veritas:revealArticle", this._revealHandler)
    this.render()
  }

  disconnect() {
    window.removeEventListener("veritas:revealArticle", this._revealHandler)
  }

  switch(event) {
    const mode = event.currentTarget.dataset.mode
    if (mode === this.currentMode) return

    this.btnTargets.forEach(btn => btn.classList.remove("active"))
    event.currentTarget.classList.add("active")

    this.currentMode = mode
    this.visibleCount = this.perPage
    this.render()
    this.listTarget.scrollTop = 0
  }

  cycleThreat() {
    this.threatIndex = (this.threatIndex + 1) % THREAT_LEVELS.length
    this.visibleCount = this.perPage
    this.render()
    this.listTarget.scrollTop = 0
  }

  loadMore() {
    this.visibleCount += this.perPage
    this.render()
  }

  _revealArticle(event) {
    const articleId = String(event.detail?.articleId)
    if (!articleId) return

    // Find which card contains this article
    const targetCard = this.cardTargets.find(
      card => card.dataset.articleId === articleId
    )
    if (!targetCard) return

    // Switch to the correct mode (hot/recent) based on card's feed set
    const cardSet = targetCard.dataset.feedSet
    const neededMode = cardSet === "hot" ? "hot" : "recent"
    if (this.currentMode !== neededMode) {
      this.currentMode = neededMode
      this.btnTargets.forEach(btn => {
        btn.classList.toggle("active", btn.dataset.mode === neededMode)
      })
    }

    // Reset threat filter to "all" so the card is not filtered out
    this.threatIndex = 0

    // Expand visible count until the card would be shown
    const cardsInSet = this.cardTargets.filter(c => c.dataset.feedSet === cardSet)
    const cardIndex = cardsInSet.indexOf(targetCard)
    if (cardIndex >= this.visibleCount) {
      this.visibleCount = cardIndex + 1
    }

    this.render()
  }

  render() {
    const setName = this.currentMode === "hot" ? "hot" : "recent"
    const threatFilter = THREAT_LEVELS[this.threatIndex]
    const cards = this.cardTargets
    let shown = 0
    let totalForMode = 0

    cards.forEach(card => {
      const cardSet = card.dataset.feedSet
      const cardThreat = card.dataset.threat

      // Must match the active set (hot or recent)
      if (cardSet !== setName) {
        card.style.display = "none"
        return
      }

      // Must match threat filter (if not "all")
      if (threatFilter.key !== "all" && cardThreat !== threatFilter.key) {
        card.style.display = "none"
        return
      }

      totalForMode++
      if (shown < this.visibleCount) {
        card.style.display = ""
        shown++
      } else {
        card.style.display = "none"
      }
    })

    // Update threat label
    if (this.hasThreatLabelTarget) {
      this.threatLabelTarget.textContent = threatFilter.label
      this.threatLabelTarget.style.color = threatFilter.color
    }

    // Update badge
    if (this.hasBadgeTarget) {
      const modeLabel = this.currentMode === "hot" ? "HOT" : this.currentMode === "recent" ? "RECENT" : "ALL"
      this.badgeTarget.textContent = `${totalForMode} ${modeLabel}`
    }

    // Show/hide load more button
    if (this.hasLoadMoreWrapTarget) {
      if (shown < totalForMode) {
        this.loadMoreWrapTarget.style.display = ""
        this.loadMoreTarget.textContent = `LOAD MORE (${totalForMode - shown} remaining)`
      } else {
        this.loadMoreWrapTarget.style.display = "none"
      }
    }
  }
}
