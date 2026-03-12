Rails.application.routes.draw do
  devise_for :users

  # -------------------------------------------------------
  # Root & Search
  # -------------------------------------------------------
  root to: "pages#home"
  get "search", to: "pages#search"
  post "chat", to: "chats#create"

  # -------------------------------------------------------
  # Read-only public resources
  # -------------------------------------------------------
  resources :articles, only: [:index, :show] do
    resources :ai_analyses, only: [:index], shallow: true
    resources :narrative_arcs, only: [:index], shallow: true
  end

  resources :regions, only: [:index, :show] do
    resources :countries, only: [:index], shallow: true
  end

  resources :perspective_filters, only: [:index, :show]
  resources :narrative_convergences, only: [:index, :show]

  # -------------------------------------------------------
  # Admin namespace (protected routes)
  # -------------------------------------------------------
  namespace :admin do
    resources :users do
      member do
        patch :toggle_admin
      end
    end
    resources :articles
    resources :regions
    resources :countries
    resources :ai_analyses
    resources :narrative_arcs
    resources :briefings
    resources :perspective_filters
    resources :feed_snapshots
  end

  # Health check
  get "up" => "rails/health#show", as: :rails_health_check
end

