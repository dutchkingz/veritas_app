import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["output"]

  connect() {
    this.fetchWeather()
  }

  fetchWeather() {
    if ("geolocation" in navigator) {
      this.outputTarget.textContent = "Locating..."
      navigator.geolocation.getCurrentPosition(
        (position) => {
          this.loadData(position.coords.latitude, position.coords.longitude)
        },
        (error) => {
          console.error("Geolocation error:", error)
          this.outputTarget.textContent = "Weather unavailable"
        }
      )
    } else {
      this.outputTarget.textContent = "Weather unavailable"
    }
  }

  async loadData(lat, lng) {
    try {
      this.outputTarget.textContent = "Fetching weather..."
      // Using Open-Meteo free API
      const url = `https://api.open-meteo.com/v1/forecast?latitude=${lat}&longitude=${lng}&current_weather=true&temperature_unit=celsius`
      const response = await fetch(url)
      const data = await response.json()

      if (data.current_weather) {
        const temp = Math.round(data.current_weather.temperature)
        const code = data.current_weather.weathercode
        const icon = this.getWeatherIcon(code)

        this.outputTarget.textContent = `${temp}°C ${icon}`
        this.outputTarget.setAttribute("title", `Weather Code: ${code}`)
      } else {
        this.outputTarget.textContent = "Weather err"
      }
    } catch (error) {
      console.error("Weather fetch error:", error)
      this.outputTarget.textContent = "Weather err"
    }
  }

  // Very basic WMO weather interpretation
  getWeatherIcon(code) {
    if (code === 0) return "☀️"
    if (code >= 1 && code <= 3) return "🌤️"
    if (code >= 45 && code <= 48) return "🌫️"
    if (code >= 51 && code <= 67) return "🌧️"
    if (code >= 71 && code <= 77) return "❄️"
    if (code >= 80 && code <= 82) return "🌦️"
    if (code >= 95 && code <= 99) return "⛈️"
    return "☁️"
  }
}
