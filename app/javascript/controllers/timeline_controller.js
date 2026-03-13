import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { min: Number, max: Number }
  static targets = ["scrubber", "date", "liveBtn"]

  connect() {
    this.scrubberTarget.value = 100
    this._updateLabel(null)
  }

  scrub() {
    const value = parseInt(this.scrubberTarget.value)

    if (value === 100) {
      this.goLive()
      return
    }

    const range = this.maxValue - this.minValue
    if (range === 0) return  // all articles at same timestamp — slider is inert

    const timestamp = Math.round(this.minValue + (value / 100) * range)
    this._updateLabel(timestamp)

    clearTimeout(this._debounce)
    this._debounce = setTimeout(() => {
      window.dispatchEvent(new CustomEvent("veritas:timelineChange", {
        detail: { toTimestamp: timestamp }
      }))
    }, 300)
  }

  goLive() {
    this.scrubberTarget.value = 100
    this._updateLabel(null)
    window.dispatchEvent(new CustomEvent("veritas:timelineChange", {
      detail: { toTimestamp: null }
    }))
  }

  rewind() {
    this.scrubberTarget.value = 0
    this.scrub()
  }

  _updateLabel(timestamp) {
    if (!timestamp) {
      this.dateTarget.textContent = "LIVE"
      this.liveBtnTarget.classList.add("is-active")
      return
    }

    this.liveBtnTarget.classList.remove("is-active")
    const d = new Date(timestamp * 1000)
    const pad = n => String(n).padStart(2, "0")
    this.dateTarget.textContent =
      `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}`
  }
}
