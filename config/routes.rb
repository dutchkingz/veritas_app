Rails.application.routes.draw do
  devise_for :users

  # -------------------------------------------------------
  # Root & Search
  # -------------------------------------------------------
  root to: "pages#welcome"
  get "welcome", to: "pages#welcome"
  get "dashboard", to: "pages#home"
  get "search", to: "pages#search"
  post "chat", to: "chats#create"
  
  # Globe & Search APIs
  get  "api/globe_data",                    to: "pages#globe_data"
  get  "api/narrative_dna/:article_id",     to: "pages#narrative_dna",    as: :narrative_dna
  get  "api/tribunal/:article_id",          to: "pages#tribunal",         as: :tribunal
  get  "api/article_preview/:article_id",   to: "pages#article_preview",  as: :article_preview
  get  "api/trending_topics",               to: "api/trending_topics#index"
  get  "api/search_suggestions",            to: "api/search_suggestions#index"
  post "api/surge_check",                   to: "api/surge_checks#create"

  # -------------------------------------------------------
  # Read-only public resources
  # -------------------------------------------------------
  resources :articles, only: [:index, :show] do
    member do
      get :analysis_status
    end
    resources :ai_analyses, only: [:index], shallow: true, controller: "feature_previews", defaults: { feature: "ai_analyses" }
    resources :narrative_arcs, only: [:index], shallow: true, controller: "feature_previews", defaults: { feature: "narrative_arcs" }
  end

  resources :regions, only: [:index, :show], controller: "feature_previews", defaults: { feature: "regions" } do
    resources :countries, only: [:index], shallow: true, controller: "feature_previews", defaults: { feature: "countries" }
  end

  resources :perspective_filters, only: [:index, :show], controller: "feature_previews", defaults: { feature: "perspective_filters" }
  resources :saved_articles, only: [:index, :show, :create, :destroy] do
    collection do
      get :watchlist
    end
  end
  resources :narrative_convergences, only: [:index, :show] do
    collection do
      post :run_detection
    end
  end

  resources :briefings, only: [:index, :show, :create]
  resource  :model_config, only: [:show, :update]

  resources :intelligence_reports, only: %i[create show] do
    member do
      get :status
    end
  end

  # -------------------------------------------------------
  # Admin namespace (protected routes)
  # -------------------------------------------------------
  namespace :admin do
    resources :users do
      member do
        patch :toggle_admin
      end
      collection do
        post :invite
      end
    end
    
    # Narrative route generation endpoint
    post "narrative_routes/generate", to: "narrative_routes#generate", as: :narrative_routes_generate
    
    resources :articles, controller: "feature_previews", defaults: { feature: "admin_articles" }
    resources :regions, controller: "feature_previews", defaults: { feature: "admin_regions" }
    resources :countries, controller: "feature_previews", defaults: { feature: "admin_countries" }
    resources :ai_analyses, controller: "feature_previews", defaults: { feature: "admin_ai_analyses" }
    resources :narrative_arcs, controller: "feature_previews", defaults: { feature: "admin_narrative_arcs" }
    resources :briefings, controller: "feature_previews", defaults: { feature: "admin_briefings" }
    resources :perspective_filters, controller: "feature_previews", defaults: { feature: "admin_perspective_filters" }
    resources :feed_snapshots, controller: "feature_previews", defaults: { feature: "admin_feed_snapshots" }
  end

  # Health check
  get "up" => "rails/health#show", as: :rails_health_check
end
