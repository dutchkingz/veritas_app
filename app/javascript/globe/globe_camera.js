// Globe Camera — flyTo, auto-rotate sync, and rotation timer management.

export class GlobeCamera {
  constructor(globeGetter) {
    this._getGlobe = globeGetter
    this._rotateTimer = null
    this._arcResumeTimer = null
    this._pointHovered = false
    this._arcHovered = false
  }

  get pointHovered() { return this._pointHovered }
  set pointHovered(v) { this._pointHovered = v; this.syncAutoRotate() }

  get arcHovered() { return this._arcHovered }
  set arcHovered(v) {
    this._arcHovered = v
    clearTimeout(this._arcResumeTimer)
    if (v) {
      // Immediately stop rotation when hovering an arc
      this._setAutoRotate(false)
    } else {
      // Delay before resuming rotation — prevents flicker on thin arcs
      this._arcResumeTimer = setTimeout(() => this.syncAutoRotate(), 300)
    }
  }

  flyTo(lat, lng, altitude = 1.5) {
    const globe = this._getGlobe()
    if (!globe) return
    const controls = globe.controls()
    controls.autoRotate = false
    globe.pointOfView({ lat, lng, altitude }, 1200)
    clearTimeout(this._rotateTimer)
    this._rotateTimer = setTimeout(() => this.syncAutoRotate(), 6000)
  }

  syncAutoRotate() {
    this._setAutoRotate(!(this._pointHovered || this._arcHovered))
  }

  _setAutoRotate(enabled) {
    const globe = this._getGlobe()
    if (!globe) return
    const controls = globe.controls()
    controls.autoRotate = enabled
  }

  dispose() {
    clearTimeout(this._rotateTimer)
    clearTimeout(this._arcResumeTimer)
  }
}
