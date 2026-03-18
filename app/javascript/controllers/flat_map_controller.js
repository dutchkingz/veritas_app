import { Controller } from "@hotwired/stimulus"
import * as d3 from "d3"
import * as topojson from "topojson-client"

const THREAT_COLORS = {
  3: "#ff3a5e",
  2: "#ffc107",
  1: "#00ff87"
}

export default class extends Controller {
  static values = { dataUrl: String }

  async connect() {
    this._margin = { top: 0, right: 0, bottom: 0, left: 0 }
    this._width = this.element.clientWidth
    this._height = this.element.clientHeight
    
    this._initSvg()
    await this._loadGeoJson()
    
    this._perspectiveHandler = (e) => this._onPerspectiveChange(e)
    this._timelineHandler = (e) => this._onTimelineChange(e)
    this._searchHandler = (e) => this._onSearchEvent(e)
    this._projectionHandler = (e) => this._onProjectionChange(e)
    
    window.addEventListener("veritas:perspectiveChange", this._perspectiveHandler)
    window.addEventListener("veritas:timelineChange", this._timelineHandler)
    window.addEventListener("veritas:search", this._searchHandler)
    window.addEventListener("veritas:mapProjectionChanged", this._projectionHandler)
    
    this._currentPerspective = localStorage.getItem("veritas:perspective") || "all"
    this._loadData()
    
    this._resizeObserver = new ResizeObserver(() => this._handleResize())
    this._resizeObserver.observe(this.element)
  }

  disconnect() {
    window.removeEventListener("veritas:perspectiveChange", this._perspectiveHandler)
    window.removeEventListener("veritas:timelineChange", this._timelineHandler)
    window.removeEventListener("veritas:search", this._searchHandler)
    window.removeEventListener("veritas:mapProjectionChanged", this._projectionHandler)
    if (this._resizeObserver) this._resizeObserver.disconnect()
  }

  _initSvg() {
    this.svg = d3.select(this.element)
      .append("svg")
      .attr("viewBox", `0 0 ${this._width} ${this._height}`)
      .attr("preserveAspectRatio", "xMidYMid meet")

    this.g = this.svg.append("g")

    // Projection & Path
    this.projection = d3.geoEquirectangular()
      .scale(this._width / (2 * Math.PI))
      .translate([this._width / 2, this._height / 2])

    this.path = d3.geoPath().projection(this.projection)

    // Layer groups (order matters for depth)
    this.gridLayer = this.g.append("g").attr("class", "grid-layer")
    this.landLayer = this.g.append("g").attr("class", "land-layer")
    this.ringsLayer = this.g.append("g").attr("class", "rings-layer")
    this.arcsLayer = this.g.append("g").attr("class", "arcs-layer")
    this.pointsLayer = this.g.append("g").attr("class", "points-layer")

    // Add Grid
    const graticule = d3.geoGraticule()
    this.gridLayer.append("path")
      .datum(graticule)
      .attr("class", "graticule")
      .attr("d", this.path)

    // Zoom behavior
    this.zoom = d3.zoom()
      .scaleExtent([1, 10])
      .on("zoom", (event) => {
        this.g.attr("transform", event.transform)
        // Scale elements slightly less than the zoom to keep them visible
        this.pointsLayer.selectAll("circle").attr("stroke-width", 0.5 / event.transform.k)
        this.arcsLayer.selectAll("path").attr("stroke-width", d => (d.thickness || 1.5) / event.transform.k)
      })

    this.svg.call(this.zoom)

  }

  async _loadGeoJson() {
    try {
      // High-quality low-res world boundaries
      const data = await d3.json("https://cdn.jsdelivr.net/npm/world-atlas@2/countries-110m.json")
      const countries = topojson.feature(data, data.objects.countries)
      
      this.landLayer.selectAll("path")
        .data(countries.features)
        .enter()
        .append("path")
        .attr("class", "land")
        .attr("d", this.path)
    } catch (e) {
      console.error("[FlatMap] Failed to load GeoJSON:", e)
    }
  }

  async _loadData(params = {}) {
    try {
      // Prevent infinite loops and useless fetches if the container is hidden
      if (this.element.clientWidth === 0) {
        return
      }

      const queryParams = new URLSearchParams()
      if (this._currentPerspective && this._currentPerspective !== "all") {
        queryParams.set("perspective_id", this._currentPerspective)
      }
      if (this._currentTimestamp) {
        queryParams.set("to", this._currentTimestamp)
      }
      // Always use segment view for narrative tracks
      queryParams.set("view", "segments")
      
      Object.entries(params).forEach(([k, v]) => queryParams.set(k, v))

      const response = await fetch(`${this.dataUrlValue}?${queryParams.toString()}`)
      const data     = await response.json()
      
      this._renderPoints(data.points || [])
      this._renderArcs(data.arcs || [])
      this._renderRings(data.regions || [])
    } catch (e) {
      console.error("[FlatMap] Data load error:", e)
    }
  }

  _renderPoints(points) {
    const bubbles = this.pointsLayer.selectAll(".signal-point")
      .data(points, d => d.id)

    bubbles.exit().remove()

    bubbles.enter()
      .append("circle")
      .attr("class", "signal-point")
      .attr("r", 0)
      .attr("fill", d => d.color || "#00f0ff")
      .attr("cx", d => this.projection([d.lng, d.lat])[0])
      .attr("cy", d => this.projection([d.lng, d.lat])[1])
      .merge(bubbles)
      .transition().duration(800)
      .attr("r", 4) // Slightly larger
      .attr("cx", d => {
        const p = this.projection([d.lng, d.lat])
        return p ? p[0] : 0
      })
      .attr("cy", d => {
        const p = this.projection([d.lng, d.lat])
        return p ? p[1] : 0
      })
  }

  _renderArcs(arcs) {
    const lines = this.arcsLayer.selectAll(".narrative-arc")
      .data(arcs, (d, i) => `${d.articleId}-${i}`)

    lines.exit().remove()

    lines.enter()
      .append("path")
      .attr("class", "narrative-arc")
      .attr("fill", "none")
      .attr("stroke", d => {
        let c = d.color || "#00f0ff"
        return Array.isArray(c) ? c[0] : c
      })
      .attr("stroke-width", d => (d.thickness || 1.5))
      .attr("d", d => {
        const start = this.projection([d.startLng, d.startLat])
        const end = this.projection([d.endLng, d.endLat])
        if (!start || !end) return ""
        // Improved quadratic curve logic for flat maps
        const dx = end[0] - start[0]
        const dy = end[1] - start[1]
        const dr = Math.sqrt(dx * dx + dy * dy)
        const midX = (start[0] + end[0]) / 2
        const midY = (start[1] + end[1]) / 2 - dr * 0.2
        return `M${start[0]},${start[1]} Q${midX},${midY} ${end[0]},${end[1]}`
      })
      .attr("stroke-dasharray", function() { return this.getTotalLength() })
      .attr("stroke-dashoffset", function() { return this.getTotalLength() })
      .merge(lines)
      // Enhance brightness for the permanent dark mode
      .attr("stroke", d => {
        let c = d.color || "#00f0ff"
        return Array.isArray(c) ? c[0] : c
      })
      .attr("opacity", 0.7)
      .transition().duration(1500)
      .attr("stroke-dashoffset", 0)
      .transition().duration(500)
      .attr("opacity", 1)
  }

  _renderRings(regions) {
    // Pulsing rings for regions
    const rings = this.ringsLayer.selectAll(".threat-ring-group")
      .data(regions, d => d.id)

    rings.exit().remove()

    const enter = rings.enter().append("g").attr("class", "threat-ring-group")
    
    const pos = d => this.projection([d.lng, d.lat])

    enter.each(function(d) {
      const g = d3.select(this)
      const color = THREAT_COLORS[d.threat] || "#00f0ff"
      const center = pos(d)

      function pulse() {
        g.append("circle")
          .attr("class", "threat-ring")
          .attr("cx", center[0])
          .attr("cy", center[1])
          .attr("r", 2)
          .attr("stroke", color)
          .attr("opacity", 0.8)
          .transition()
          .duration(2000)
          .attr("r", 20)
          .attr("opacity", 0)
          .remove()
          .on("end", pulse)
      }
      pulse()
    })
  }

  _onPerspectiveChange(e) {
    this._currentPerspective = e.detail.perspectiveId
    this._loadData()
  }

  _onTimelineChange(e) {
    this._currentTimestamp = e.detail.toTimestamp
    this._loadData()
  }

  _onSearchEvent(e) {
    this._loadData({ search_query: e.detail.query })
  }

  _onProjectionChange(e) {
    if (e.detail.mode === "flat") {
      this._loadData()
    }
  }

  _handleResize() {
    this._width = this.element.clientWidth
    this._height = this.element.clientHeight
    this.svg.attr("viewBox", `0 0 ${this._width} ${this._height}`)
    this.projection
      .scale(this._width / (2 * Math.PI))
      .translate([this._width / 2, this._height / 2])
    this.g.selectAll("path").attr("d", this.path)
    this._loadData()
  }
}
