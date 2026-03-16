import { Controller } from "@hotwired/stimulus"
import consumer from "channels/consumer"

export default class extends Controller {
  static targets = ["queryInput", "trendingContainer", "resultsContainer", "searchForm"]
  static values = { currentQuery: String }

  connect() {
    this._setupAutocomplete()
    this._loadTrendingTopics()
    
    // Listen for search results updates
    this._subscription = consumer.subscriptions.create("SearchChannel", {
      received: (data) => this._onSearchUpdate(data)
    })
    
    console.log("[SearchController] connected")
  }

  disconnect() {
    this._subscription?.unsubscribe()
  }

  // Trigger search when form is submitted
  submit(event) {
    // Don't prevent default - let the form submit normally
    // This ensures the search page loads with results
    const query = this.queryInputTarget.value.trim()
    
    if (!query) return
    
    // Also dispatch event for Globe to filter (if on globe page)
    this._dispatchGlobeFilter(query)
  }

  // Clear search and reset globe
  clear() {
    this.queryInputTarget.value = ''
    this.currentQueryValue = ''
    
    // Dispatch event to reset globe
    window.dispatchEvent(new CustomEvent('veritas:searchClear'))
    
    // Reset URL
    const url = new URL(window.location)
    url.searchParams.delete('q')
    window.history.pushState({}, '', url)
    
    this.element.classList.remove('is-searching')
  }

  // Load trending topics from API
  async _loadTrendingTopics() {
    try {
      const response = await fetch('/api/trending_topics')
      const data = await response.json()
      
      if (data.topics && this.hasTrendingContainerTarget) {
        this._renderTrendingTopics(data.topics)
      }
    } catch (err) {
      console.error('[SearchController] Failed to load trending topics:', err)
    }
  }

  // Render trending topic tags
  _renderTrendingTopics(topics) {
    this.trendingContainerTarget.innerHTML = `
      <div class="trending-topics">
        <div class="trending-label">
          <i class="fa fa-fire text-danger me-2"></i>
          TRENDING INTELLIGENCE TOPICS
        </div>
        <div class="trending-tags">
          ${topics.map(topic => `
            <button 
              class="trending-tag"
              data-action="click->search#selectTrending"
              data-topic="${topic.keyword}"
              style="--tag-color: ${topic.color || '#38BDF8'};"
            >
              ${topic.keyword}
              <span class="topic-count">${topic.count}</span>
            </button>
          `).join('')}
        </div>
      </div>
    `
  }

  // User clicked a trending topic
  selectTrending(event) {
    const topic = event.target.dataset.topic
    this.queryInputTarget.value = topic
    this.submit(event)
  }

  // Dispatch custom event for Globe controller to filter
  _dispatchGlobeFilter(query) {
    window.dispatchEvent(new CustomEvent('veritas:search', {
      detail: {
        query: query,
        timestamp: Date.now()
      }
    }))
  }

  // Receive updates from SearchChannel (real-time results)
  _onSearchUpdate(data) {
    if (data.type === 'results_loaded') {
      this.element.classList.remove('is-searching')
      
      // Update results container if present
      if (this.hasResultsContainerTarget && data.html) {
        this.resultsContainerTarget.innerHTML = data.html
      }
    }
  }

  // Setup autocomplete (optional enhancement)
  _setupAutocomplete() {
    if (!this.hasQueryInputTarget) return
    
    let debounceTimer
    
    this.queryInputTarget.addEventListener('input', (e) => {
      clearTimeout(debounceTimer)
      debounceTimer = setTimeout(() => {
        this._fetchSuggestions(e.target.value)
      }, 300)
    })
  }

  async _fetchSuggestions(query) {
    if (query.length < 3) return
    
    try {
      const response = await fetch(`/api/search_suggestions?q=${encodeURIComponent(query)}`)
      const data = await response.json()
      
      // TODO: Render autocomplete dropdown
      console.log('Suggestions:', data.suggestions)
    } catch (err) {
      console.error('[SearchController] Failed to fetch suggestions:', err)
    }
  }
}
