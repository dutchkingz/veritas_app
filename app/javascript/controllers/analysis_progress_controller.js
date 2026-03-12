import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["bar", "label", "result", "button"]

  static values = {
    regionId: Number,
    reportId: Number,
    pollInterval: { type: Number, default: 2500 }
  }

  STATUS_WIDTHS = {
    pending:    "15%",
    processing: "60%",
    completed:  "100%",
    failed:     "100%"
  }

  STATUS_LABELS = {
    pending:    "Signal Queued...",
    processing: "Analysing Signal Intelligence...",
    completed:  "Briefing Ready.",
    failed:     "System Failure."
  }

  connect() {
    // Controller connects on page load, but does NOT poll yet.
    // It waits for the user to click the RUN button.
  }

  disconnect() {
    this.#stopPolling()
  }

  // ------------------------------------------------------------------
  // Actions
  // ------------------------------------------------------------------

  // Triggered by data-action="click->analysis-progress#run"
  async run(event) {
    event.preventDefault()
    
    // Disable UI
    if (this.hasButtonTarget) {
      this.buttonTarget.disabled = true
      this.buttonTarget.textContent = "WAIT"
    }

    try {
      const response = await fetch("/intelligence_reports", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": this.#csrfToken()
        },
        body: JSON.stringify({ region_id: this.regionIdValue })
      })

      if (!response.ok) throw new Error("Network response was not ok")

      const data = await response.json()
      this.reportIdValue = data.report_id
      
      this.#applyStatus(data.status)
      this.#startPolling()
    } catch (error) {
      console.error("[AnalysisProgress] Run error:", error)
      this.#applyStatus("failed")
    }
  }

  // ------------------------------------------------------------------
  // Private
  // ------------------------------------------------------------------

  #startPolling() {
    this.#stopPolling() // Clear any existing
    this._pollTimer = setInterval(() => this.#poll(), this.pollIntervalValue)
  }

  #stopPolling() {
    if (this._pollTimer) clearInterval(this._pollTimer)
  }

  async #poll() {
    if (!this.reportIdValue) return

    try {
      const res = await fetch(`/intelligence_reports/${this.reportIdValue}/status`, {
        headers: { Accept: "application/json" }
      })

      if (!res.ok) return

      const data = await res.json()
      this.#applyStatus(data.status)

      if (data.status === "completed" || data.status === "failed") {
        this.#stopPolling()
        if (data.status === "completed") this.#showLink()
      }
    } catch (err) {
      console.warn("[AnalysisProgress] Polling error:", err)
    }
  }

  #applyStatus(status) {
    const width = this.STATUS_WIDTHS[status]  || "0%"
    const label = this.STATUS_LABELS[status]  || "Working..."
    const colour = status === "failed" ? "var(--neon-red)" : "var(--neon-blue)"

    if (this.hasBarTarget) {
      this.barTarget.style.width = width
      this.barTarget.style.background = `linear-gradient(90deg, ${colour}, rgba(0,0,0,0))`
    }
    if (this.hasLabelTarget) {
      this.labelTarget.innerHTML = `<span class="veritas-glitch-text" data-text="${label}">${label}</span>`
    }
  }

  #showLink() {
    if (!this.hasResultTarget) return
    this.resultTarget.classList.remove("d-none")
    this.resultTarget.innerHTML = `
      <a href="/intelligence_reports/${this.reportIdValue}" 
         class="btn veritas-dossier-btn w-100 mt-2">
         OPEN INTEL DOSSIER
      </a>
    `
  }

  #csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content ?? ""
  }
}
