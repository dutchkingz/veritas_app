import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.interval = setInterval(() => {
      Turbo.visit(window.location.href, { action: "replace" })
    }, 60000)
  }

  disconnect() {
    clearInterval(this.interval)
  }
}
