import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    // Wire up inline article images so they also open the lightbox
    this.element.querySelectorAll(".article-body-format img").forEach(img => {
      img.style.cursor = "pointer"
      img.addEventListener("click", () => {
        this._show(img.src, img.alt)
      })
    })
  }

  disconnect() {
    this._dismiss()
  }

  open(event) {
    const thumb = event.currentTarget
    this._show(thumb.dataset.full, thumb.dataset.caption || "")
  }

  // Build the lightbox dynamically on document.body, sized to the actual image
  _show(url, caption) {
    this._dismiss() // close any existing lightbox

    // Create overlay backdrop
    const overlay = document.createElement("div")
    overlay.className = "vt-lightbox-overlay"
    this._overlay = overlay

    // Close button
    const closeBtn = document.createElement("button")
    closeBtn.className = "vt-lightbox-close"
    closeBtn.innerHTML = "&#10005;"
    closeBtn.addEventListener("click", () => this._dismiss())

    // Image element — we load it first to get natural dimensions
    const img = document.createElement("img")
    img.className = "vt-lightbox-img"
    img.alt = caption || ""
    img.addEventListener("click", () => this._dismiss())

    // Caption
    const cap = document.createElement("p")
    cap.className = "vt-lightbox-caption"
    if (caption) cap.textContent = caption

    // Container that wraps image + caption, sized dynamically
    const container = document.createElement("div")
    container.className = "vt-lightbox-container"
    container.appendChild(closeBtn)
    container.appendChild(img)
    if (caption) container.appendChild(cap)

    overlay.appendChild(container)
    overlay.addEventListener("click", (e) => {
      if (e.target === overlay) this._dismiss()
    })

    document.body.appendChild(overlay)

    // Escape key
    this._boundKey = (e) => { if (e.key === "Escape") this._dismiss() }
    document.addEventListener("keydown", this._boundKey)

    // Set src after appending — let the image load, then the CSS handles sizing
    img.src = url

    // Trigger open animation on next frame
    requestAnimationFrame(() => overlay.classList.add("vt-lightbox--open"))
  }

  _dismiss() {
    if (this._overlay) {
      this._overlay.classList.remove("vt-lightbox--open")
      // Remove after fade-out
      setTimeout(() => {
        this._overlay?.remove()
        this._overlay = null
      }, 200)
    }
    if (this._boundKey) {
      document.removeEventListener("keydown", this._boundKey)
      this._boundKey = null
    }
  }
}
