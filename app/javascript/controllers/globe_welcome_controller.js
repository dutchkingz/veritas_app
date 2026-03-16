import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["container"]

  async connect() {
    this._initGlobe()
  }

  disconnect() {
    if (this._globe) {
      if (this._globe._destructor) this._globe._destructor()
    }
    if (this._resizeObserver) {
      this._resizeObserver.disconnect()
    }
  }

  async _initGlobe() {
    try {
      const Globe = (await import("globe.gl")).default
      const THREE = await import("three")
      const container = this.containerTarget

      if (!container) return

      // Use a clearer daylight texture
      this._globe = Globe()(container)
        .globeImageUrl("//unpkg.com/three-globe/example/img/earth-blue-marble.jpg")
        .bumpImageUrl("//unpkg.com/three-globe/example/img/earth-topology.png")
        .backgroundColor("rgba(0,0,0,0)") 
        .showAtmosphere(true)
        .atmosphereColor("#00f0ff")
        .atmosphereAltitude(0.25)
        .width(container.clientWidth || window.innerWidth)
        .height(container.clientHeight || window.innerHeight)

      const scene = this._globe.scene()
      
      // Remove any default lights to have full control
      const lightsToRemove = []
      scene.traverse(obj => {
        if (obj.isLight) lightsToRemove.push(obj)
      })
      lightsToRemove.forEach(l => scene.remove(l))

      // VERY STRONG ambient light for "Daylight" effect everywhere
      const ambientLight = new THREE.AmbientLight(0xffffff, 2.5)
      scene.add(ambientLight)

      // Multiple directional lights to ensure no dark parts while rotating
      const sunLight1 = new THREE.DirectionalLight(0xffffff, 2.0)
      sunLight1.position.set(1, 1, 1).normalize()
      scene.add(sunLight1)

      const sunLight2 = new THREE.DirectionalLight(0xffffff, 1.5)
      sunLight2.position.set(-1, -1, 1).normalize()
      scene.add(sunLight2)

      const controls = this._globe.controls()
      controls.autoRotate = true
      controls.autoRotateSpeed = 1.0 // Slightly faster for dynamism
      controls.enableZoom = false
      controls.enablePan = false

      // Closer perspective to make it look "much bigger"
      this._globe.pointOfView({ lat: 20, lng: 10, altitude: 1.8 }, 0)

      this._resizeObserver = new ResizeObserver(() => {
        if (this._globe && container.clientWidth) {
          this._globe.width(container.clientWidth).height(container.clientHeight)
        }
      })
      this._resizeObserver.observe(container)
      
      // Ensure the globe mesh is fully illuminated
      scene.traverse(obj => {
        if (obj.isMesh) {
          obj.material.lightMapIntensity = 2
          obj.material.needsUpdate = true
        }
      })

    } catch (error) {
      console.error("Globe init error:", error)
    }
  }
}
