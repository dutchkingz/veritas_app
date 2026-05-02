import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { min: Number, max: Number }
  static targets = ["scrubber", "date", "liveBtn", "playBtn", "speedBtn"]

  connect() {
    this.scrubberTarget.value = 100
    this._updateLabel(null)
    this._playing = false
    this._speed = 1
    this._animFrame = null
  }

  disconnect() {
    this._stopPlayback()
  }

  scrub() {
    const value = parseInt(this.scrubberTarget.value)

    if (value === 100) {
      this.goLive()
      return
    }

    // If user manually scrubs, pause playback
    if (this._playing) this._stopPlayback()

    const range = this.maxValue - this.minValue
    if (range === 0) return

    const timestamp = Math.round(this.minValue + (value / 100) * range)
    this._updateLabel(timestamp)

    clearTimeout(this._debounce)
    this._debounce = setTimeout(() => {
      window.dispatchEvent(new CustomEvent("veritas:timelineChange", {
        detail: { toTimestamp: timestamp }
      }))
    }, 100)
  }

  goLive() {
    this._stopPlayback()
    this.scrubberTarget.value = 100
    this._updateLabel(null)
    window.dispatchEvent(new CustomEvent("veritas:timelineChange", {
      detail: { toTimestamp: null }
    }))
  }

  rewind() {
    this._stopPlayback()
    this.scrubberTarget.value = 0
    this.scrub()
  }

  // -------------------------------------------------------
  // DVR Playback
  // -------------------------------------------------------

  togglePlay() {
    if (this._playing) {
      this._stopPlayback()
    } else {
      this._startPlayback()
    }
  }

  cycleSpeed() {
    const speeds = [1, 2, 4]
    const idx = speeds.indexOf(this._speed)
    this._speed = speeds[(idx + 1) % speeds.length]
    if (this.hasSpeedBtnTarget) {
      this.speedBtnTarget.textContent = `${this._speed}x`
    }
  }

  _startPlayback() {
    // If at LIVE (100%), start from beginning
    if (parseInt(this.scrubberTarget.value) >= 100) {
      this.scrubberTarget.value = 0
    }

    this._playing = true
    this._lastFrameTime = performance.now()
    if (this.hasPlayBtnTarget) this.playBtnTarget.textContent = "⏸"

    this._tick()
  }

  _stopPlayback() {
    this._playing = false
    if (this._animFrame) cancelAnimationFrame(this._animFrame)
    this._animFrame = null
    if (this.hasPlayBtnTarget) this.playBtnTarget.textContent = "▶"
  }

  _tick() {
    if (!this._playing) return

    const now = performance.now()
    const elapsed = now - this._lastFrameTime
    this._lastFrameTime = now

    // Advance the scrubber: full sweep takes ~30 seconds at 1x speed
    const increment = (elapsed / 30000) * 100 * this._speed
    let current = parseFloat(this.scrubberTarget.value) + increment

    if (current >= 100) {
      current = 100
      this._stopPlayback()
    }

    this.scrubberTarget.value = current

    const range = this.maxValue - this.minValue
    if (range > 0 && current < 100) {
      const timestamp = Math.round(this.minValue + (current / 100) * range)
      this._updateLabel(timestamp)

      window.dispatchEvent(new CustomEvent("veritas:timelineChange", {
        detail: { toTimestamp: timestamp }
      }))
    } else if (current >= 100) {
      this.goLive()
      return
    }

    this._animFrame = requestAnimationFrame(() => this._tick())
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
