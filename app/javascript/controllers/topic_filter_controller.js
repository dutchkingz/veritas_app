import { Controller } from "@hotwired/stimulus"

const STORAGE_KEY = "veritas:topic"

export default class extends Controller {
  static targets = ["pill"]

  connect() {
    const saved = localStorage.getItem(STORAGE_KEY) || null
    this._currentTopic = saved
    this._activatePill(saved)
  }

  toggle(event) {
    const topic = event.currentTarget.dataset.topic
    if (!topic) return

    // Toggle off if same pill clicked again
    const next = this._currentTopic === topic ? null : topic
    this._currentTopic = next

    if (next) {
      localStorage.setItem(STORAGE_KEY, next)
    } else {
      localStorage.removeItem(STORAGE_KEY)
    }

    this._activatePill(next)
    window.dispatchEvent(new CustomEvent("veritas:topicFilter", {
      detail: { topic: next }
    }))
  }

  _activatePill(topic) {
    this.pillTargets.forEach(pill => {
      pill.classList.toggle("is-active", pill.dataset.topic === topic)
    })
  }
}
