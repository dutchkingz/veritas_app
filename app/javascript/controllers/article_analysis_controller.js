import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    statusUrl: String,
    status: String,
    pollInterval: { type: Number, default: 4000 }
  }

  connect() {
    if (!this._shouldPoll()) return

    this._schedulePoll()
  }

  disconnect() {
    clearTimeout(this._pollTimer)
  }

  async poll() {
    if (!this._shouldPoll()) return

    try {
      const response = await fetch(this.statusUrlValue, {
        headers: { Accept: "application/json" }
      })
      if (!response.ok) return this._schedulePoll()

      const data = await response.json()
      if (data.complete) {
        window.location.reload()
        return
      }

      if (data.failed) {
        window.location.reload()
        return
      }

      this.statusValue = data.status
    } catch (_error) {
      // Polling is best-effort; a later cycle can recover from transient failures.
    }

    this._schedulePoll()
  }

  _schedulePoll() {
    clearTimeout(this._pollTimer)
    this._pollTimer = setTimeout(() => this.poll(), this.pollIntervalValue)
  }

  _shouldPoll() {
    return this.hasStatusUrlValue && ["queued", "analyzing"].includes(this.statusValue)
  }
}
