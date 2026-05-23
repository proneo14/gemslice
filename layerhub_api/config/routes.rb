Rails.application.routes.draw do
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Devise routes — placed outside namespace so helpers stay as
  # `current_user` / `authenticate_user!` (not `current_api_v1_user`)
  devise_for :users,
    path: "api/v1",
    path_names: {
      sign_in: "login",
      sign_out: "logout",
      registration: "signup"
    },
    controllers: {
      sessions: "api/v1/sessions",
      registrations: "api/v1/registrations"
    }

  namespace :api do
    namespace :v1 do
      resources :projects do
        resources :print_assets
      end

      # Slice endpoints
      post "print_assets/:print_asset_id/slice", to: "slice_jobs#create"
      resources :slice_jobs, only: [:show] do
        member do
          get :download
        end
      end
    end
  end
end
