import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["overlay", "img", "caption"]

  connect() {
    // Wire up inline article images so they also open the lightbox
    this.element.querySelectorAll(".article-body-format img").forEach(img => {
      img.style.cursor = "pointer"
      img.addEventListener("click", () => {
        this._show(img.src, img.alt)
      })
    })
  }

  open(event) {
    const thumb = event.currentTarget
    this._show(thumb.dataset.full, thumb.dataset.caption || "")
  }

  close() {
    this.overlayTarget.classList.remove("lightbox--open")
    this.imgTarget.src = ""
    document.removeEventListener("keydown", this._boundKey)
  }

  backdropClick(event) {
    if (event.target === this.overlayTarget) this.close()
  }

  // private

  _show(url, caption) {
    this.imgTarget.src            = url
    this.captionTarget.textContent = caption
    this.overlayTarget.classList.add("lightbox--open")
    this._boundKey = (e) => { if (e.key === "Escape") this.close() }
    document.addEventListener("keydown", this._boundKey)
  }
}
