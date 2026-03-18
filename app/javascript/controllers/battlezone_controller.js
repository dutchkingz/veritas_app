import { Controller } from "@hotwired/stimulus"

// ─── VERITAS Battlezone ───────────────────────────────────────
// Easter-egg: Battlezone (1980) × TRON (1982)
// First-person wireframe tank combat with cyan neon palette.
// Triggered by clicking the A.W.A.R.E hero image.
// ──────────────────────────────────────────────────────────────

const C = {
  cyan:      "#00d4ff",
  cyanDim:   "rgba(0,212,255,0.15)",
  cyanMid:   "rgba(0,212,255,0.4)",
  cyanGlow:  "rgba(0,212,255,0.6)",
  green:     "#00ff87",
  greenDim:  "rgba(0,255,135,0.3)",
  red:       "#ff3a5e",
  redDim:    "rgba(255,58,94,0.25)",
  redGlow:   "rgba(255,58,94,0.4)",
  bg:        "#09090f",
  text:      "#e8edf2",
  gridDim:   "rgba(0,212,255,0.3)",
  gridMid:   "rgba(0,212,255,0.6)",
  gridBright:"rgba(0,212,255,0.9)",
}

const GRID_SIZE    = 10
const GRID_EXTENT  = 200
const NEAR_CLIP    = 1.0
const CAM_HEIGHT   = 2.5
const PLAYER_SPEED = 30
const TURN_SPEED   = 2.2
const BULLET_SPEED = 80
const FIRE_COOLDOWN = 0.35
const HIT_INVULN   = 1.8
const FIELD_RADIUS  = 180

export default class extends Controller {
  connect() {
    this.element.style.cursor = "pointer"
  }

  disconnect() {
    this._close()
  }

  // ── Launch overlay on click ──

  launch(event) {
    event.preventDefault()
    event.stopPropagation()
    if (this._backdrop) return

    // Overlay
    this._backdrop = document.createElement("div")
    this._backdrop.className = "battlezone-backdrop"
    this._backdrop.innerHTML = `
      <div class="battlezone-container">
        <canvas class="battlezone-canvas"></canvas>
        <button class="battlezone-close" aria-label="Close">&times;</button>
      </div>`
    document.body.appendChild(this._backdrop)

    this._canvas = this._backdrop.querySelector("canvas")
    this._ctx    = this._canvas.getContext("2d")
    this._closeBtn = this._backdrop.querySelector(".battlezone-close")
    this._closeBtn.addEventListener("click", () => this._close())

    this._sizeCanvas()
    this._resizeObs = new ResizeObserver(() => this._sizeCanvas())
    this._resizeObs.observe(this._backdrop)

    // Input
    this._keys = new Set()
    this._keyDown = (e) => this._onKeyDown(e)
    this._keyUp   = (e) => this._onKeyUp(e)
    document.addEventListener("keydown", this._keyDown)
    document.addEventListener("keyup",   this._keyUp)

    // Audio
    try { this._audio = new AudioContext() } catch (_) { this._audio = null }

    this._initGame()
    this._running = true
    this._lastTime = performance.now()
    this._raf = requestAnimationFrame((t) => this._loop(t))
  }

  // ── Close & cleanup ──

  _close() {
    this._running = false
    if (this._raf) cancelAnimationFrame(this._raf)
    if (this._resizeObs) this._resizeObs.disconnect()
    document.removeEventListener("keydown", this._keyDown)
    document.removeEventListener("keyup",   this._keyUp)
    if (this._audio) { try { this._audio.close() } catch (_) {} }
    if (this._backdrop) {
      this._backdrop.classList.add("battlezone-backdrop--closing")
      setTimeout(() => { this._backdrop?.remove(); this._backdrop = null }, 250)
    }
  }

  // ── Canvas sizing ──

  _sizeCanvas() {
    const maxW = Math.min(window.innerWidth - 40, 960)
    const maxH = Math.min(window.innerHeight - 40, 720)
    const aspect = 4 / 3
    let w = maxW, h = maxW / aspect
    if (h > maxH) { h = maxH; w = maxH * aspect }
    this._canvas.width  = Math.round(w)
    this._canvas.height = Math.round(h)
    this._focal = this._canvas.width * 0.55
    this._cx = this._canvas.width  / 2
    this._cy = this._canvas.height / 2
  }

  // ── Input ──

  _onKeyDown(e) {
    if (e.key === "Escape") { this._close(); return }
    const k = e.key === " " ? " " : e.key.toLowerCase()
    this._keys.add(k)
    if ([" ", "arrowup", "arrowdown", "arrowleft", "arrowright"].includes(k)) {
      e.preventDefault()
    }
    // Queue fire on keydown so quick taps are never missed
    if (k === " ") this._fireQueued = true
    if (e.key === "Enter" && (this._state === "start" || this._state === "gameover")) {
      this._initGame()
      this._state = "playing"
    }
  }

  _onKeyUp(e) {
    const k = e.key === " " ? " " : e.key.toLowerCase()
    this._keys.delete(k)
  }

  _key(k) { return this._keys.has(k) }

  // ── Game state init ──

  _initGame() {
    this._fireQueued = false
    this._player = { x: 0, z: 0, rot: 0, cooldown: 0, lives: 3, invuln: 0 }
    this._enemies     = []
    this._bullets      = []
    this._explosions   = []
    this._score        = 0
    this._wave         = 1
    this._waveTimer    = 2.0
    this._waveSpawned  = false
    this._state        = "start"   // start | playing | wavepause | gameover
    this._screenFlash  = 0
  }

  // ── Main loop ──

  _loop(ts) {
    if (!this._running) return
    const dt = Math.min((ts - this._lastTime) / 1000, 0.05)
    this._lastTime = ts

    if (this._state === "playing" || this._state === "wavepause") {
      this._update(dt)
    }

    this._render()
    this._raf = requestAnimationFrame((t) => this._loop(t))
  }

  // ── Update ──

  _update(dt) {
    const p = this._player

    // Player movement
    if (this._key("a") || this._key("arrowleft"))  p.rot -= TURN_SPEED * dt
    if (this._key("d") || this._key("arrowright")) p.rot += TURN_SPEED * dt
    const fwd = (this._key("w") || this._key("arrowup")) ? 1 : (this._key("s") || this._key("arrowdown")) ? -1 : 0
    if (fwd) {
      p.x += Math.sin(p.rot) * PLAYER_SPEED * fwd * dt
      p.z += Math.cos(p.rot) * PLAYER_SPEED * fwd * dt
    }
    // Clamp to field
    const dist = Math.sqrt(p.x * p.x + p.z * p.z)
    if (dist > FIELD_RADIUS) {
      p.x *= FIELD_RADIUS / dist
      p.z *= FIELD_RADIUS / dist
    }

    // Fire — accept held key OR queued tap
    p.cooldown = Math.max(0, p.cooldown - dt)
    p.invuln   = Math.max(0, p.invuln - dt)
    const wantsFire = this._key(" ") || this._fireQueued
    this._fireQueued = false
    if (wantsFire && p.cooldown <= 0 && this._state === "playing") {
      p.cooldown = FIRE_COOLDOWN
      this._bullets.push({
        x: p.x + Math.sin(p.rot) * 2,
        z: p.z + Math.cos(p.rot) * 2,
        dx: Math.sin(p.rot) * BULLET_SPEED,
        dz: Math.cos(p.rot) * BULLET_SPEED,
        isPlayer: true, age: 0
      })
      this._playSound("shoot")
    }

    // Update bullets
    this._bullets.forEach(b => {
      b.x += b.dx * dt
      b.z += b.dz * dt
      b.age += dt
    })
    this._bullets = this._bullets.filter(b => b.age < 3)

    // Update enemies
    this._enemies.forEach(e => {
      if (!e.alive) return
      const dx = p.x - e.x, dz = p.z - e.z
      const d  = Math.sqrt(dx * dx + dz * dz)
      const targetRot = Math.atan2(dx, dz)

      // Rotate toward player
      let diff = targetRot - e.rot
      while (diff >  Math.PI) diff -= 2 * Math.PI
      while (diff < -Math.PI) diff += 2 * Math.PI
      e.rot += Math.sign(diff) * Math.min(Math.abs(diff), e.turnSpeed * dt)

      // Move forward
      e.x += Math.sin(e.rot) * e.speed * dt
      e.z += Math.cos(e.rot) * e.speed * dt

      // Fire at player
      e.cooldown -= dt
      if (e.cooldown <= 0 && d < 120 && this._state === "playing") {
        e.cooldown = e.fireRate
        this._bullets.push({
          x: e.x + Math.sin(e.rot) * 2,
          z: e.z + Math.cos(e.rot) * 2,
          dx: Math.sin(e.rot) * BULLET_SPEED * 0.7,
          dz: Math.cos(e.rot) * BULLET_SPEED * 0.7,
          isPlayer: false, age: 0
        })
      }
    })

    // Collisions: player bullets → enemies
    this._bullets.filter(b => b.isPlayer).forEach(b => {
      this._enemies.forEach(e => {
        if (!e.alive) return
        if (this._dist(b, e) < 3) {
          e.alive = false
          b.age = 99
          this._score += 100 * this._wave
          this._explosions.push({ x: e.x, z: e.z, r: 0, max: 6, alpha: 1 })
          this._playSound("hit")
        }
      })
    })

    // Collisions: enemy bullets → player
    if (p.invuln <= 0) {
      const hit = this._bullets.find(b => !b.isPlayer && this._dist(b, p) < 2.5)
      if (hit) {
        hit.age = 99
        this._playerHit()
      }
      // Enemy ram
      const ram = this._enemies.find(e => e.alive && this._dist(e, p) < 4)
      if (ram) {
        ram.alive = false
        this._explosions.push({ x: ram.x, z: ram.z, r: 0, max: 6, alpha: 1 })
        this._playerHit()
      }
    }

    // Explosions
    this._explosions.forEach(ex => {
      ex.r += 20 * dt
      ex.alpha -= 1.2 * dt
    })
    this._explosions = this._explosions.filter(ex => ex.alpha > 0)

    // Screen flash
    this._screenFlash = Math.max(0, this._screenFlash - 3 * dt)

    // Wave management
    if (this._state === "playing" && !this._waveSpawned) {
      this._spawnWave()
      this._waveSpawned = true
    }

    if (this._state === "playing" && this._enemies.every(e => !e.alive) && this._waveSpawned) {
      this._state = "wavepause"
      this._waveTimer = 2.0
      this._score += 500 * this._wave
    }

    if (this._state === "wavepause") {
      this._waveTimer -= dt
      if (this._waveTimer <= 0) {
        this._wave++
        this._waveSpawned = false
        this._state = "playing"
      }
    }
  }

  _playerHit() {
    const p = this._player
    p.lives--
    p.invuln = HIT_INVULN
    this._screenFlash = 1
    this._explosions.push({ x: p.x, z: p.z, r: 0, max: 8, alpha: 1 })
    this._playSound("death")
    if (p.lives <= 0) {
      this._state = "gameover"
    }
  }

  _spawnWave() {
    const count = 2 + this._wave
    const speed = Math.min(12 + this._wave * 3, 35)
    const rate  = Math.max(1.5, 4 - this._wave * 0.3)
    for (let i = 0; i < count; i++) {
      const angle = (Math.PI * 2 * i) / count + Math.random() * 0.5
      const r = 80 + Math.random() * 70
      this._enemies.push({
        x: this._player.x + Math.sin(angle) * r,
        z: this._player.z + Math.cos(angle) * r,
        rot: Math.random() * Math.PI * 2,
        speed: speed + Math.random() * 5,
        turnSpeed: 1.5 + Math.random() * 0.5,
        fireRate: rate + Math.random(),
        cooldown: rate * Math.random(),
        alive: true
      })
    }
  }

  // ── 3D projection ──

  _transform(wx, wy, wz) {
    const p = this._player
    const dx = wx - p.x, dz = wz - p.z, dy = wy - CAM_HEIGHT
    const s = Math.sin(p.rot), c = Math.cos(p.rot)
    return { x: dx * c - dz * s, y: dy, z: dx * s + dz * c }
  }

  _project(wx, wy, wz) {
    const t = this._transform(wx, wy, wz)
    if (t.z < NEAR_CLIP) return null
    return {
      sx: this._cx + (this._focal * t.x) / t.z,
      sy: this._cy - (this._focal * t.y) / t.z,
      z: t.z
    }
  }

  // ── Render ──

  _render() {
    const ctx = this._ctx
    const w = this._canvas.width, h = this._canvas.height
    ctx.clearRect(0, 0, w, h)

    // Background
    ctx.fillStyle = C.bg
    ctx.fillRect(0, 0, w, h)

    if (this._state === "start") {
      this._renderStartScreen(ctx, w, h)
      return
    }

    // Horizon line — TRON glow
    ctx.strokeStyle = C.gridMid
    ctx.shadowColor = C.cyan
    ctx.shadowBlur = 6
    ctx.lineWidth = 1.5
    ctx.beginPath()
    ctx.moveTo(0, this._cy)
    ctx.lineTo(w, this._cy)
    ctx.stroke()
    ctx.shadowBlur = 0

    this._renderGround(ctx)
    this._renderBullets(ctx)
    this._renderEnemies(ctx)
    this._renderExplosions(ctx)
    this._renderBarrel(ctx, w, h)
    this._renderHUD(ctx, w, h)
    this._renderRadar(ctx, w, h)

    // Screen flash on hit
    if (this._screenFlash > 0) {
      ctx.fillStyle = `rgba(255,58,94,${this._screenFlash * 0.3})`
      ctx.fillRect(0, 0, w, h)
    }

    // Invulnerability flicker
    if (this._player.invuln > 0 && Math.floor(this._player.invuln * 8) % 2 === 0) {
      ctx.strokeStyle = C.redDim
      ctx.lineWidth = 2
      ctx.strokeRect(4, 4, w - 8, h - 8)
    }

    // Wave pause overlay
    if (this._state === "wavepause") {
      ctx.fillStyle = C.cyan
      ctx.font = `bold ${Math.round(h * 0.04)}px "JetBrains Mono", monospace`
      ctx.textAlign = "center"
      ctx.fillText(`WAVE ${this._wave} COMPLETE`, w / 2, h * 0.45)
    }

    // Game over
    if (this._state === "gameover") {
      this._renderGameOver(ctx, w, h)
    }
  }

  _renderStartScreen(ctx, w, h) {
    ctx.textAlign = "center"

    // Title
    ctx.shadowColor = C.cyan
    ctx.shadowBlur = 20
    ctx.fillStyle = C.cyan
    ctx.font = `bold ${Math.round(h * 0.08)}px "JetBrains Mono", monospace`
    ctx.fillText("BATTLEZONE", w / 2, h * 0.32)
    ctx.shadowBlur = 0

    ctx.fillStyle = C.text
    ctx.font = `${Math.round(h * 0.025)}px "JetBrains Mono", monospace`
    ctx.fillText("VERITAS DEFENSE TRAINING SIMULATION", w / 2, h * 0.40)

    // Controls
    ctx.fillStyle = C.cyanGlow
    ctx.font = `${Math.round(h * 0.022)}px "JetBrains Mono", monospace`
    const controls = [
      "W / \u2191  FORWARD        S / \u2193  REVERSE",
      "A / \u2190  ROTATE LEFT    D / \u2192  ROTATE RIGHT",
      "SPACE  FIRE            ESC  EXIT"
    ]
    controls.forEach((line, i) => {
      ctx.fillText(line, w / 2, h * 0.52 + i * h * 0.04)
    })

    // Prompt
    const blink = Math.floor(Date.now() / 500) % 2
    if (blink) {
      ctx.fillStyle = C.green
      ctx.font = `bold ${Math.round(h * 0.03)}px "JetBrains Mono", monospace`
      ctx.fillText("PRESS ENTER TO BEGIN", w / 2, h * 0.75)
    }

    // Decorative grid
    ctx.strokeStyle = C.gridDim
    ctx.lineWidth = 1
    for (let i = 0; i <= 20; i++) {
      const x = (w / 20) * i
      ctx.beginPath(); ctx.moveTo(x, h * 0.85); ctx.lineTo(w / 2, h * 0.78); ctx.stroke()
    }
  }

  _renderGameOver(ctx, w, h) {
    ctx.fillStyle = "rgba(9,9,15,0.7)"
    ctx.fillRect(0, 0, w, h)

    ctx.textAlign = "center"
    ctx.shadowColor = C.red
    ctx.shadowBlur = 20
    ctx.fillStyle = C.red
    ctx.font = `bold ${Math.round(h * 0.07)}px "JetBrains Mono", monospace`
    ctx.fillText("GAME OVER", w / 2, h * 0.38)
    ctx.shadowBlur = 0

    ctx.fillStyle = C.text
    ctx.font = `${Math.round(h * 0.03)}px "JetBrains Mono", monospace`
    ctx.fillText(`FINAL SCORE: ${this._score}`, w / 2, h * 0.48)
    ctx.fillText(`WAVE REACHED: ${this._wave}`, w / 2, h * 0.54)

    const blink = Math.floor(Date.now() / 500) % 2
    if (blink) {
      ctx.fillStyle = C.cyan
      ctx.font = `bold ${Math.round(h * 0.025)}px "JetBrains Mono", monospace`
      ctx.fillText("PRESS ENTER TO RESTART", w / 2, h * 0.68)
    }
  }

  // ── Ground grid ──

  _renderGround(ctx) {
    ctx.lineWidth = 1.5

    for (let i = -GRID_EXTENT; i <= GRID_EXTENT; i += GRID_SIZE) {
      // Z-parallel lines
      this._drawGridLine(ctx, i, 0, -GRID_EXTENT, i, 0, GRID_EXTENT)
      // X-parallel lines
      this._drawGridLine(ctx, -GRID_EXTENT, 0, i, GRID_EXTENT, 0, i)
    }
  }

  _drawGridLine(ctx, x1, y1, z1, x2, y2, z2) {
    let a = this._transform(x1, y1, z1)
    let b = this._transform(x2, y2, z2)

    // Clip behind camera
    if (a.z < NEAR_CLIP && b.z < NEAR_CLIP) return
    if (a.z < NEAR_CLIP) a = this._clipToNear(a, b)
    if (b.z < NEAR_CLIP) b = this._clipToNear(b, a)

    const ax = this._cx + (this._focal * a.x) / a.z
    const ay = this._cy - (this._focal * a.y) / a.z
    const bx = this._cx + (this._focal * b.x) / b.z
    const by = this._cy - (this._focal * b.y) / b.z

    const avgZ = (a.z + b.z) / 2
    if (avgZ < 20) {
      ctx.strokeStyle = C.gridBright
      ctx.shadowColor = C.cyan
      ctx.shadowBlur = 6
    } else if (avgZ < 60) {
      ctx.strokeStyle = C.gridMid
      ctx.shadowColor = C.cyan
      ctx.shadowBlur = 4
    } else {
      ctx.strokeStyle = C.gridDim
      ctx.shadowColor = C.cyan
      ctx.shadowBlur = 2
    }
    ctx.beginPath()
    ctx.moveTo(ax, ay)
    ctx.lineTo(bx, by)
    ctx.stroke()
    ctx.shadowBlur = 0
  }

  _clipToNear(behind, infront) {
    const t = (NEAR_CLIP - behind.z) / (infront.z - behind.z)
    return {
      x: behind.x + (infront.x - behind.x) * t,
      y: behind.y + (infront.y - behind.y) * t,
      z: NEAR_CLIP
    }
  }

  // ── Bullets ──

  _renderBullets(ctx) {
    this._bullets.forEach(b => {
      const p = this._project(b.x, 0.8, b.z)
      if (!p || p.z > 150) return
      const size = Math.max(2, 6 / p.z * 10)
      ctx.shadowColor = b.isPlayer ? C.green : C.red
      ctx.shadowBlur = 8
      ctx.fillStyle = b.isPlayer ? C.green : C.red
      ctx.fillRect(p.sx - size / 2, p.sy - size / 2, size, size)
      ctx.shadowBlur = 0
    })
  }

  // ── Enemy tanks ──

  _renderEnemies(ctx) {
    // Sort back-to-front
    const sorted = this._enemies.filter(e => e.alive).map(e => {
      const t = this._transform(e.x, 0, e.z)
      return { ...e, viewZ: t.z }
    }).filter(e => e.viewZ > NEAR_CLIP).sort((a, b) => b.viewZ - a.viewZ)

    sorted.forEach(e => {
      const p = this._project(e.x, 0, e.z)
      if (!p) return
      const scale = Math.min(this._focal / p.z * 0.06, 4)
      this._drawTank(ctx, p.sx, p.sy, scale, e.rot - this._player.rot)
    })
  }

  _drawTank(ctx, sx, sy, scale, relRot) {
    const s = scale * 18
    ctx.strokeStyle = C.red
    ctx.lineWidth = 1.5
    ctx.shadowColor = C.redGlow
    ctx.shadowBlur = 6

    // Hull — trapezoidal body
    ctx.beginPath()
    ctx.moveTo(sx - s,     sy + s * 0.3)
    ctx.lineTo(sx - s * 0.7, sy - s * 0.5)
    ctx.lineTo(sx + s * 0.7, sy - s * 0.5)
    ctx.lineTo(sx + s,     sy + s * 0.3)
    ctx.closePath()
    ctx.stroke()

    // Turret
    const tw = s * 0.4
    ctx.beginPath()
    ctx.moveTo(sx - tw, sy - s * 0.2)
    ctx.lineTo(sx - tw, sy - s * 0.6)
    ctx.lineTo(sx + tw, sy - s * 0.6)
    ctx.lineTo(sx + tw, sy - s * 0.2)
    ctx.closePath()
    ctx.stroke()

    // Barrel
    const barrelDir = relRot
    const bx = Math.sin(barrelDir) * s * 0.8
    ctx.beginPath()
    ctx.moveTo(sx, sy - s * 0.5)
    ctx.lineTo(sx + bx, sy - s * 0.9)
    ctx.stroke()

    // Treads
    ctx.strokeStyle = C.redDim
    ctx.lineWidth = 1
    ctx.beginPath()
    ctx.moveTo(sx - s * 1.05, sy + s * 0.35)
    ctx.lineTo(sx - s * 1.05, sy - s * 0.15)
    ctx.stroke()
    ctx.beginPath()
    ctx.moveTo(sx + s * 1.05, sy + s * 0.35)
    ctx.lineTo(sx + s * 1.05, sy - s * 0.15)
    ctx.stroke()

    ctx.shadowBlur = 0
  }

  // ── Explosions ──

  _renderExplosions(ctx) {
    this._explosions.forEach(ex => {
      const p = this._project(ex.x, 1, ex.z)
      if (!p) return
      const r = (ex.r / ex.max) * 40 * Math.min(this._focal / p.z * 0.05, 3)
      ctx.strokeStyle = `rgba(0,255,135,${ex.alpha})`
      ctx.lineWidth = 2
      ctx.shadowColor = C.greenDim
      ctx.shadowBlur = 10

      // Expanding wireframe burst — multiple rings
      for (let i = 0; i < 3; i++) {
        const rr = r * (0.5 + i * 0.3)
        ctx.beginPath()
        ctx.arc(p.sx, p.sy, rr, 0, Math.PI * 2)
        ctx.stroke()
      }

      // Cross-lines
      ctx.beginPath()
      ctx.moveTo(p.sx - r, p.sy); ctx.lineTo(p.sx + r, p.sy)
      ctx.moveTo(p.sx, p.sy - r); ctx.lineTo(p.sx, p.sy + r)
      ctx.stroke()

      ctx.shadowBlur = 0
    })
  }

  // ── Player barrel (bottom of viewport) ──

  _renderBarrel(ctx, w, h) {
    ctx.strokeStyle = C.cyanMid
    ctx.lineWidth = 2
    // Two converging lines from bottom corners toward crosshair
    ctx.beginPath()
    ctx.moveTo(w * 0.38, h)
    ctx.lineTo(w * 0.48, h * 0.78)
    ctx.stroke()
    ctx.beginPath()
    ctx.moveTo(w * 0.62, h)
    ctx.lineTo(w * 0.52, h * 0.78)
    ctx.stroke()
  }

  // ── HUD ──

  _renderHUD(ctx, w, h) {
    ctx.shadowBlur = 0
    const font = (s) => `${Math.round(h * s)}px "JetBrains Mono", monospace`

    // Periscope frame
    ctx.strokeStyle = C.cyanDim
    ctx.lineWidth = 3
    // Top arc viewport shape
    ctx.beginPath()
    ctx.moveTo(0, h)
    ctx.lineTo(0, h * 0.12)
    ctx.quadraticCurveTo(0, 0, w * 0.15, 0)
    ctx.lineTo(w * 0.85, 0)
    ctx.quadraticCurveTo(w, 0, w, h * 0.12)
    ctx.lineTo(w, h)
    ctx.stroke()

    // Inner frame line
    ctx.strokeStyle = "rgba(0,212,255,0.07)"
    ctx.lineWidth = 1
    const m = 12
    ctx.strokeRect(m, m, w - m * 2, h - m * 2)

    // Crosshair
    ctx.strokeStyle = C.cyan
    ctx.lineWidth = 1
    const gap = 8, arm = 20
    ctx.beginPath()
    ctx.moveTo(this._cx - arm, this._cy); ctx.lineTo(this._cx - gap, this._cy)
    ctx.moveTo(this._cx + gap, this._cy); ctx.lineTo(this._cx + arm, this._cy)
    ctx.moveTo(this._cx, this._cy - arm); ctx.lineTo(this._cx, this._cy - gap)
    ctx.moveTo(this._cx, this._cy + gap); ctx.lineTo(this._cx, this._cy + arm)
    ctx.stroke()

    // Small center dot
    ctx.fillStyle = C.cyan
    ctx.beginPath()
    ctx.arc(this._cx, this._cy, 1.5, 0, Math.PI * 2)
    ctx.fill()

    // Score (top-left)
    ctx.textAlign = "left"
    ctx.fillStyle = C.cyan
    ctx.font = font(0.025)
    ctx.fillText("SCORE", 24, 30)
    ctx.font = `bold ${font(0.035)}`
    ctx.fillText(String(this._score).padStart(6, "0"), 24, 56)

    // Wave (top-center)
    ctx.textAlign = "center"
    ctx.fillStyle = C.text
    ctx.font = font(0.022)
    ctx.fillText(`WAVE ${String(this._wave).padStart(2, "0")}`, w / 2, 30)

    // Lives (top-right)
    ctx.textAlign = "right"
    ctx.fillStyle = C.cyan
    ctx.font = font(0.025)
    ctx.fillText("LIVES", w - 24, 30)
    // Tank icons for lives
    for (let i = 0; i < this._player.lives; i++) {
      const lx = w - 30 - i * 28
      ctx.strokeStyle = C.green
      ctx.lineWidth = 1
      ctx.beginPath()
      ctx.moveTo(lx - 8, 52); ctx.lineTo(lx - 5, 42); ctx.lineTo(lx + 5, 42); ctx.lineTo(lx + 8, 52)
      ctx.closePath()
      ctx.stroke()
      ctx.beginPath()
      ctx.moveTo(lx, 44); ctx.lineTo(lx, 38)
      ctx.stroke()
    }

    // Bottom label
    ctx.textAlign = "center"
    ctx.fillStyle = C.cyanMid
    ctx.font = font(0.018)
    ctx.fillText("VERITAS DEFENSE TRAINING // CLASSIFIED", w / 2, h - 14)
  }

  // ── Radar ──

  _renderRadar(ctx, w, h) {
    const rx = w / 2, ry = h - 64, rr = 44

    // Radar background
    ctx.fillStyle = "rgba(9,9,15,0.8)"
    ctx.beginPath()
    ctx.arc(rx, ry, rr + 2, 0, Math.PI * 2)
    ctx.fill()

    ctx.strokeStyle = C.cyanDim
    ctx.lineWidth = 1
    ctx.beginPath()
    ctx.arc(rx, ry, rr, 0, Math.PI * 2)
    ctx.stroke()

    // Grid lines
    ctx.beginPath()
    ctx.moveTo(rx - rr, ry); ctx.lineTo(rx + rr, ry)
    ctx.moveTo(rx, ry - rr); ctx.lineTo(rx, ry + rr)
    ctx.stroke()

    ctx.beginPath()
    ctx.arc(rx, ry, rr * 0.5, 0, Math.PI * 2)
    ctx.stroke()

    // Player direction indicator
    const pdx = Math.sin(this._player.rot) * rr * 0.3
    const pdz = -Math.cos(this._player.rot) * rr * 0.3
    ctx.strokeStyle = C.green
    ctx.lineWidth = 2
    ctx.beginPath()
    ctx.moveTo(rx, ry)
    ctx.lineTo(rx + pdx, ry + pdz)
    ctx.stroke()

    // Player dot
    ctx.fillStyle = C.green
    ctx.beginPath()
    ctx.arc(rx, ry, 3, 0, Math.PI * 2)
    ctx.fill()

    // Enemy blips
    const radarScale = rr / 150
    this._enemies.forEach(e => {
      if (!e.alive) return
      const dx = (e.x - this._player.x) * radarScale
      const dz = -(e.z - this._player.z) * radarScale
      const bx = rx + dx, by = ry + dz
      if (Math.sqrt(dx * dx + dz * dz) > rr) return
      ctx.fillStyle = C.red
      ctx.beginPath()
      ctx.arc(bx, by, 2.5, 0, Math.PI * 2)
      ctx.fill()
    })
  }

  // ── Audio (Web Audio oscillator bleeps) ──

  _playSound(type) {
    if (!this._audio || this._audio.state !== "running") {
      try { this._audio?.resume() } catch (_) {}
      if (!this._audio || this._audio.state !== "running") return
    }

    const osc = this._audio.createOscillator()
    const gain = this._audio.createGain()
    osc.connect(gain)
    gain.connect(this._audio.destination)
    const now = this._audio.currentTime

    switch (type) {
      case "shoot":
        osc.type = "square"
        osc.frequency.setValueAtTime(800, now)
        osc.frequency.exponentialRampToValueAtTime(400, now + 0.05)
        gain.gain.setValueAtTime(0.08, now)
        gain.gain.exponentialRampToValueAtTime(0.001, now + 0.08)
        osc.start(now); osc.stop(now + 0.08)
        break
      case "hit":
        osc.type = "sawtooth"
        osc.frequency.setValueAtTime(600, now)
        osc.frequency.exponentialRampToValueAtTime(150, now + 0.15)
        gain.gain.setValueAtTime(0.1, now)
        gain.gain.exponentialRampToValueAtTime(0.001, now + 0.2)
        osc.start(now); osc.stop(now + 0.2)
        break
      case "death":
        osc.type = "sawtooth"
        osc.frequency.setValueAtTime(200, now)
        osc.frequency.exponentialRampToValueAtTime(60, now + 0.3)
        gain.gain.setValueAtTime(0.12, now)
        gain.gain.exponentialRampToValueAtTime(0.001, now + 0.35)
        osc.start(now); osc.stop(now + 0.35)
        break
    }
  }

  // ── Helpers ──

  _dist(a, b) {
    const dx = a.x - b.x, dz = a.z - b.z
    return Math.sqrt(dx * dx + dz * dz)
  }
}
