# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"
pin "bootstrap", to: "bootstrap.min.js", preload: true
pin "@popperjs/core", to: "popper.js", preload: true

# ActionCable — WebSocket consumer
pin "@rails/actioncable", to: "actioncable.esm.js"
pin_all_from "app/javascript/channels", under: "channels"

# Globe.gl — 3D globe visualisation for the war room
pin "globe.gl", to: "https://cdn.jsdelivr.net/npm/globe.gl@2.41.2/+esm"
pin "three", to: "https://ga.jspm.io/npm:three@0.160.0/build/three.module.js"

# D3.js — Force-directed network graphs (Narrative DNA)
pin "d3", to: "https://cdn.jsdelivr.net/npm/d3@7/+esm"
pin "topojson-client", to: "https://cdn.jsdelivr.net/npm/topojson-client@3/+esm"
