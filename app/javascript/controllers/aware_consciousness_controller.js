import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["counter", "progressBar", "loopNode", "narration", "audioBtn"]

  connect() {
    this.animatedElements = new Set()
    this.setupIntersectionObserver()
    this.fadeInLoopNodes()
    this.startLoopPulse()
    this.startTypewriter()
    this.startNarrationAudio()
  }

  disconnect() {
    if (this.observer) this.observer.disconnect()
    if (this.pulseInterval) clearInterval(this.pulseInterval)
    if (this.typewriterTimer) clearTimeout(this.typewriterTimer)
    if (this._audio) { this._audio.pause(); this._audio = null }
  }

  // ── IntersectionObserver: counters & bars animate on scroll ──

  setupIntersectionObserver() {
    this.observer = new IntersectionObserver((entries) => {
      entries.forEach((entry) => {
        if (!entry.isIntersecting || this.animatedElements.has(entry.target)) return
        this.animatedElements.add(entry.target)

        if (entry.target.dataset.countTo !== undefined) {
          this.animateCounter(entry.target)
        }
        if (entry.target.dataset.fillTo !== undefined) {
          this.animateProgressBar(entry.target)
        }
      })
    }, { threshold: 0.2 })

    this.counterTargets.forEach((el) => this.observer.observe(el))
    this.progressBarTargets.forEach((el) => this.observer.observe(el))
  }

  // ── Animated counter: 0 → value over 1.5s with ease-out ──

  animateCounter(el) {
    const target = parseFloat(el.dataset.countTo)
    const duration = 1500
    const start = performance.now()
    const isFloat = String(target).includes(".")

    const step = (now) => {
      const t = Math.min((now - start) / duration, 1)
      const eased = 1 - Math.pow(1 - t, 3)
      const current = target * eased
      el.textContent = isFloat ? current.toFixed(1) : Math.round(current)
      if (t < 1) requestAnimationFrame(step)
    }

    requestAnimationFrame(step)
  }

  // ── Progress bar: width 0% → value over 1.2s ──

  animateProgressBar(el) {
    setTimeout(() => {
      el.style.width = `${el.dataset.fillTo}%`
    }, 200)
  }

  // ── Compounding loop pulse: cycle active class through nodes ──

  startLoopPulse() {
    if (!this.hasLoopNodeTarget) return
    const nodes = this.loopNodeTargets
    let idx = 0
    const interval = 4000 / nodes.length

    const pulse = () => {
      nodes.forEach((n) => n.classList.remove("aware-loop-node--active"))
      nodes[idx].classList.add("aware-loop-node--active")
      idx = (idx + 1) % nodes.length
    }

    // First pulse after fade-in completes
    setTimeout(() => {
      pulse()
      this.pulseInterval = setInterval(pulse, interval)
    }, nodes.length * 200 + 400)
  }

  // ── Loop nodes: staggered fade-in ──

  fadeInLoopNodes() {
    this.loopNodeTargets.forEach((node, i) => {
      node.style.opacity = "0"
      node.style.transform = "translateY(12px)"
      setTimeout(() => {
        node.style.transition = "opacity 0.5s ease, transform 0.5s ease"
        node.style.opacity = "1"
        node.style.transform = "translateY(0)"
      }, i * 200)
    })
  }

  // ── Typewriter: reveal narration word-by-word ──

  startTypewriter() {
    if (!this.hasNarrationTarget) return
    const el = this.narrationTarget
    const text = el.dataset.narrationText || ""
    if (!text) return

    el.textContent = ""
    el.classList.add("aware-narration--typing")

    const words = text.split(" ")
    let i = 0

    const type = () => {
      if (i < words.length) {
        el.textContent += (i > 0 ? " " : "") + words[i]
        i++
        this.typewriterTimer = setTimeout(type, 33)
      } else {
        el.classList.remove("aware-narration--typing")
        el.classList.add("aware-narration--done")
      }
    }

    setTimeout(type, 600)
  }

  // ── Narration audio: fetch TTS and autoplay ──

  async startNarrationAudio() {
    try {
      const resp = await fetch("/api/aware_narration")
      if (!resp.ok) return

      const blob = await resp.blob()
      const url = URL.createObjectURL(blob)
      this._audio = new Audio(url)
      this._audio.volume = 0.7

      // Try autoplay — browsers may block this
      try {
        await this._audio.play()
        this._showAudioBtn("playing")
      } catch (_) {
        // Autoplay blocked — show play button
        this._showAudioBtn("paused")
      }

      this._audio.addEventListener("ended", () => this._showAudioBtn("ended"))
    } catch (e) {
      // ElevenLabs unavailable — silent fallback, no button shown
    }
  }

  // ── Audio play/pause toggle (clicked from the button) ──

  toggleAudio() {
    if (!this._audio) return
    if (this._audio.paused) {
      this._audio.play()
      this._showAudioBtn("playing")
    } else {
      this._audio.pause()
      this._showAudioBtn("paused")
    }
  }

  _showAudioBtn(state) {
    if (!this.hasAudioBtnTarget) return
    const btn = this.audioBtnTarget
    btn.classList.remove("aware-audio-btn--hidden")

    if (state === "playing") {
      btn.innerHTML = '<span class="aware-audio-icon">&#9646;&#9646;</span> PAUSE'
      btn.title = "Pause narration"
    } else if (state === "paused") {
      btn.innerHTML = '<span class="aware-audio-icon">&#9654;</span> PLAY'
      btn.title = "Play narration"
    } else {
      btn.innerHTML = '<span class="aware-audio-icon">&#9654;</span> REPLAY'
      btn.title = "Replay narration"
      this._audio.currentTime = 0
    }
  }
}
