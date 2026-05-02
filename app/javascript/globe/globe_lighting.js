// Globe Lighting — manages day/night lighting states for the 3D globe.

export class GlobeLighting {
  constructor(globeGetter) {
    this._getGlobe = globeGetter
    this._isDay = true
  }

  get isDay() { return this._isDay }

  async setup() {
    await this._applyLighting()
  }

  toggle() {
    this._isDay = !this._isDay
    const globe = this._getGlobe()
    if (globe) {
      const texture = this._isDay
        ? "/globe/earth-blue-marble.jpg"
        : "/globe/earth-night.jpg"
      globe.globeImageUrl(texture)
      this._applyLighting()
    }
    window.dispatchEvent(new CustomEvent("veritas:dayNightState", {
      detail: { isDay: this._isDay }
    }))
  }

  async _applyLighting() {
    const globe = this._getGlobe()
    const scene = globe?.scene()
    if (!scene) return

    try {
      const THREE = await import("three")

      // Remove all existing lights
      const toRemove = []
      scene.traverse(obj => { if (obj.isLight) toRemove.push(obj) })
      toRemove.forEach(l => scene.remove(l))

      if (this._isDay) {
        // Bright daytime lighting
        scene.add(new THREE.AmbientLight(0xffffff, 2.0))
        const sun = new THREE.DirectionalLight(0xffffff, 1.8)
        sun.position.set(1, 1, 1).normalize()
        scene.add(sun)
        const fill = new THREE.DirectionalLight(0xffffff, 1.2)
        fill.position.set(-1, -1, 1).normalize()
        scene.add(fill)
      } else {
        // Night mode — earth-night.jpg has bright city lights on dark surface
        scene.add(new THREE.AmbientLight(0xffffff, 1.6))
        const soft = new THREE.DirectionalLight(0x8899bb, 0.4)
        soft.position.set(0, 1, 1).normalize()
        scene.add(soft)
      }

      // Update materials
      scene.traverse(obj => {
        if (obj.isMesh && obj.material) {
          obj.material.lightMapIntensity = this._isDay ? 2 : 1.5
          obj.material.needsUpdate = true
        }
      })
    } catch (e) {
      console.warn("[VERITAS Globe] Could not apply lighting:", e)
    }
  }
}
