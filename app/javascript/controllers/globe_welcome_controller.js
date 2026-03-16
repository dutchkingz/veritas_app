import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["container"]

  async connect() {
    this._initGlobe()
  }

  disconnect() {
    if (this._globe) {
      this._globe._destructor && this._globe._destructor()
    }
    if (this._resizeObserver) {
      this._resizeObserver.disconnect()
    }
  }

  async _initGlobe() {
    const Globe = (await import("globe.gl")).default
    const container = this.containerTarget

    this._globe = Globe()(container)
      .globeImageUrl("//unpkg.com/three-globe/example/img/earth-blue-marble.jpg")
      .backgroundColor("rgba(0,0,0,0)") // transparent for SCSS background
      .showAtmosphere(true)
      .atmosphereColor("#00f0ff")
      .atmosphereAltitude(0.15)
      .width(container.clientWidth)
      .height(container.clientHeight)

    const controls = this._globe.controls()
    controls.autoRotate = true
    controls.autoRotateSpeed = 0.5
    controls.enableZoom = false
    controls.enablePan = false

    this._globe.pointOfView({ lat: 20, lng: 10, altitude: 1.8 }, 0)

    this._resizeObserver = new ResizeObserver(() => {
      if (this._globe) {
        this._globe.width(container.clientWidth).height(container.clientHeight)
      }
    })
    this._resizeObserver.observe(container)
  }
}
