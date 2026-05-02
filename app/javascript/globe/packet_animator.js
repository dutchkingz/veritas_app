// Packet animation — small spheres traveling along arcs.
// Requires THREE.js and a globe instance.

export class PacketAnimator {
  constructor(globe) {
    this._globe = globe
    this._packets = []
    this._packetGroup = null
    this._animationFrameId = null
  }

  get group() { return this._packetGroup }
  get packets() { return this._packets }

  update() {
    if (!this._globe || !window.THREE) {
      console.warn("[VERITAS Globe] THREE.js not available, skipping packet animation")
      return
    }

    const scene = this._globe.scene()
    if (!scene) return

    if (!this._packetGroup) {
      this._packetGroup = new window.THREE.Group()
      scene.add(this._packetGroup)
    }

    this._packetGroup.clear()
    this._packets.length = 0

    const arcs = this._globe.arcsData()
    if (!arcs || arcs.length === 0) return

    arcs.forEach((segment) => {
      const geometry = new window.THREE.SphereGeometry(0.08, 8, 8)
      let packetColor = segment.color || '#00f0ff'
      if (Array.isArray(packetColor)) packetColor = packetColor[0]

      const material = new window.THREE.MeshBasicMaterial({
        color: packetColor,
        transparent: true,
        opacity: 0.9
      })
      const sphere = new window.THREE.Mesh(geometry, material)

      this._packets.push({
        segment,
        mesh: sphere,
        progress: Math.random() * 0.8 + 0.1,
        speed: this._calculateSpeed(segment)
      })

      this._packetGroup.add(sphere)
    })

    if (!this._animationFrameId) {
      this._animate()
    }
  }

  dispose() {
    if (this._animationFrameId) {
      cancelAnimationFrame(this._animationFrameId)
      this._animationFrameId = null
    }
    if (this._packetGroup) {
      this._packetGroup.clear()
    }
    this._packets.length = 0
  }

  _calculateSpeed(segment) {
    const baseSpeed = 0.00015
    const delayFactor = segment.delaySeconds ? Math.max(0.5, Math.min(2.0, 1800 / segment.delaySeconds)) : 1.0
    return baseSpeed * delayFactor
  }

  _animate() {
    if (!this._globe || !this._packetGroup) return

    this._packets.forEach(packet => {
      packet.progress += packet.speed
      if (packet.progress > 1.0) packet.progress = 0.0

      const startLat = packet.segment.startLat
      const startLng = packet.segment.startLng
      const endLat = packet.segment.endLat
      const endLng = packet.segment.endLng

      const lat = startLat + (endLat - startLat) * packet.progress
      const lng = startLng + (endLng - startLng) * packet.progress

      const radius = this._globe.getGlobeRadius() || 100
      const phi = (90 - lat) * Math.PI / 180
      const theta = (lng + 180) * Math.PI / 180

      const x = -radius * Math.sin(phi) * Math.cos(theta)
      const y = radius * Math.cos(phi)
      const z = radius * Math.sin(phi) * Math.sin(theta)

      const elevation = 1.02
      packet.mesh.position.set(x * elevation, y * elevation, z * elevation)
    })

    this._animationFrameId = requestAnimationFrame(() => this._animate())
  }
}
