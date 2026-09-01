Lit::Engine.routes.draw do
  if Lit.api_enabled
    namespace :api do
      namespace :v1 do
        get '/last_change' => 'localizations#last_change'
        resources :locales, only: [:index]
        resources :localization_keys, only: [:index]
        resources :localizations, only: [:index] do
          get 'last_change', on: :collection
        end
      end
    end
  end
  if Lit.ai_api_enabled
    namespace :api do
      namespace :v1 do
        namespace :ai do
          get 'pending' => 'suggestions#pending'
          post 'suggestions' => 'suggestions#create'
          post 'refresh_keys' => 'suggestions#refresh_keys'
        end
      end
    end
  end

  resources :locales, only: [:index, :destroy] do
    put :hide, on: :member
  end
  resources :localization_keys, only: [:index, :destroy] do
    member do
      get :star
      put :change_completed
      put :restore_deleted
    end
    collection do
      get :starred
      get :find_localization
      get :not_translated
      get :visited_again
      post :batch_touch
    end
    resources :localizations, only: [:edit, :update, :show] do
      member do
        put :change_completed
        get :previous_versions
      end
    end
  end
  resources :sources do
    member do
      get :synchronize
      get :sync_complete
      put :touch
    end
    resources :incomming_localizations, only: [:index, :destroy] do
      member do
        get :accept
      end
      collection do
        get :accept_all
        post :reject_all
      end
    end
  end

  resources :ai_suggestions, only: %i[index update destroy] do
    member do
      post :accept
    end
    collection do
      post :accept_all
      delete :reject_all
    end
  end

  resource :cloud_translation, only: :show
  resources :duplicates, only: :index
  resources :exports, only: [:index] do
    get :export, on: :collection
  end

  root to: 'dashboard#index'
end
