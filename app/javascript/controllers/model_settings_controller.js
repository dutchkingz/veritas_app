import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["panel", "customFields"]

  close() {
    this.element.classList.add("d-none")
  }

  closeOnBackdrop(event) {
    if (event.target === this.element) this.close()
  }

  toggleCustomEndpoint(event) {
    if (event.target.checked) {
      this.customFieldsTarget.classList.remove("d-none")
    } else {
      this.customFieldsTarget.classList.add("d-none")
    }
  }
}
