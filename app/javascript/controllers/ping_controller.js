import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["output"]

  connect() {
    this.updatePing()
    this.timer = setInterval(() => this.updatePing(), 2000)
  }

  disconnect() {
    if (this.timer) clearInterval(this.timer)
  }

  updatePing() {
    // Simulate realistic ping fluctuations (20ms - 45ms) for a tech feel
    const basePing = 22
    const jitter = Math.floor(Math.random() * 15)
    const ping = basePing + jitter
    
    if (this.hasOutputTarget) {
      this.outputTarget.textContent = `${ping}ms`
    }
  }
}
