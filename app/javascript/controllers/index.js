// Import and register all your controllers from the importmap via controllers/**/*_controller
import { application } from "controllers/application"
import { eagerLoadControllersFrom } from "@hotwired/stimulus-loading"
eagerLoadControllersFrom("controllers", application)

// Explicit registration for controllers that eagerLoad misses
import BreakingAlertController from "controllers/breaking_alert_controller"
application.register("breaking-alert", BreakingAlertController)
