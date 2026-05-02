// Globe Event Bus — centralizes window event listener registration/cleanup.

const WINDOW_EVENTS = [
  ["veritas:flyTo",             "_onFlyToEvent"],
  ["veritas:perspectiveChange", "_onPerspectiveChange"],
  ["veritas:topicFilter",       "_onTopicFilter"],
  ["veritas:timelineChange",    "_onTimelineChange"],
  ["veritas:search",            "_onSearchEvent"],
  ["veritas:searchClear",       "_onSearchClearEvent"],
  ["veritas:breakingAlert",     "_onBreakingAlert"],
  ["veritas:view-mode-changed", "_onViewModeChanged"],
  ["veritas:heatmapToggle",     "_onHeatmapToggle"],
  ["veritas:dayNightToggle",    "_onDayNightToggle"],
  ["veritas:mode-changed",      "_onModeChanged"],
  ["veritas:isolateToggle",     "_onIsolateToggle"],
  ["veritas:bloomActive",       "_onJourneyActivated"],
  ["veritas:chronicleActive",   "_onJourneyActivated"],
  ["veritas:journeyEnded",      "_onJourneyEnded"],
  ["veritas:timelapseToggle",   "_onTimelapseToggle"],
  ["veritas:backToGlobal",      "_onBackToGlobal"],
  ["veritas:exploreArticle",    "_onExploreArticle"],
]

export class GlobeEventBus {
  constructor() {
    this._handlers = []
    this._docHandler = null
  }

  bind(controller) {
    // Window events — each maps to a controller method
    WINDOW_EVENTS.forEach(([event, method]) => {
      const handler = (e) => controller[method](e)
      window.addEventListener(event, handler)
      this._handlers.push([event, handler])
    })

    // Document click for route menu dismissal
    this._docHandler = (e) => controller._handleRouteMenuDocumentClick(e)
    document.addEventListener("click", this._docHandler)
  }

  unbind() {
    this._handlers.forEach(([event, handler]) => {
      window.removeEventListener(event, handler)
    })
    this._handlers = []

    if (this._docHandler) {
      document.removeEventListener("click", this._docHandler)
      this._docHandler = null
    }
  }
}
