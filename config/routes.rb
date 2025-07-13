Rails.application.routes.draw do
  root "guilds#index"

  resources :guilds, only: [ :index, :show ] do
    member do
      get :achievements
      get :compare_queries
      post :benchmark
    end
  end

  resources :players, only: [ :index, :show ] do
    member do
      get :achievements
    end
  end

  resources :achievements, only: [ :index, :show ] do
    member do
      get :leaderboard
    end
  end
end
