defmodule NobarSyncWeb.Router do
  use NobarSyncWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
    plug NobarSyncWeb.Plugs.RateLimit, bucket: :api, limit: 300, window_ms: 60_000
    plug NobarSyncWeb.Plugs.FetchSession
    plug NobarSyncWeb.Plugs.FetchGuest
    plug NobarSyncWeb.Plugs.CSRF
  end

  pipeline :auth_tight do
    plug NobarSyncWeb.Plugs.RateLimit, bucket: :auth, limit: 20, window_ms: 60_000
  end

  pipeline :user do
    plug NobarSyncWeb.Plugs.RequireUser
  end

  pipeline :admin do
    plug NobarSyncWeb.Plugs.RequireAdmin
  end

  scope "/health", NobarSyncWeb do
    get "/live", HealthController, :live
    get "/ready", HealthController, :ready
  end

  scope "/api/v1", NobarSyncWeb do
    pipe_through [:api, :auth_tight]
    post "/auth/register", AuthController, :register
    post "/auth/login", AuthController, :login
  end

  scope "/api/v1", NobarSyncWeb do
    pipe_through :api

    post "/auth/logout", AuthController, :logout
    get "/auth/me", AuthController, :me
    get "/health", HealthController, :summary

    scope "/" do
      pipe_through :user

      post "/auth/socket-token", AuthController, :socket_token
      get "/rooms/:code", RoomController, :show
      post "/rooms/:code/join", RoomController, :join
      post "/rooms/:code/leave", RoomController, :leave
      get "/rooms/:code/playback", RoomController, :playback
      get "/rooms/:code/messages", RoomController, :messages
      post "/rooms/:code/ready", RoomController, :ready
      get "/rooms/:code/playlist", RoomController, :playlist
      post "/playback/token", PlaybackController, :token

      patch "/auth/me", AuthController, :update_me
      post "/auth/password", AuthController, :change_password
      post "/auth/avatar", AuthController, :avatar

      get "/media", MediaController, :index
      get "/media/:id", MediaController, :show
      get "/media/:id/processing", MediaController, :processing
      patch "/media/:id", MediaController, :update
      delete "/media/:id", MediaController, :delete
      post "/media/:id/subtitles", MediaController, :add_subtitle
      post "/media/youtube", MediaController, :youtube
      post "/media/import-url", MediaController, :import_url
      post "/media/drive", MediaController, :drive

      post "/media/uploads", UploadController, :create
      post "/media/uploads/:id/parts", UploadController, :part
      post "/media/uploads/:id/complete", UploadController, :complete
      post "/media/uploads/:id/abort", UploadController, :abort

      get "/rooms", RoomController, :index
      post "/rooms", RoomController, :create
      patch "/rooms/:code/settings", RoomController, :settings
      post "/rooms/:code/close", RoomController, :close
      delete "/rooms/:code", RoomController, :delete
      post "/rooms/:code/lock", RoomController, :lock
      post "/rooms/:code/kick", RoomController, :kick
      post "/rooms/:code/transfer-host", RoomController, :transfer
      post "/rooms/:code/media", RoomController, :set_media
      post "/rooms/:code/playlist", RoomController, :add_playlist
      delete "/rooms/:code/playlist/:item_id", RoomController, :remove_playlist
      post "/rooms/:code/playlist/:item_id/vote", RoomController, :vote
      post "/rooms/:code/invitations", RoomController, :invite
    end

    scope "/admin" do
      pipe_through [:user, :admin]
      get "/users", AdminController, :users
      patch "/users/:id", AdminController, :update_user
      post "/users/:id/revoke-sessions", AdminController, :revoke_sessions
      get "/audit", AdminController, :audit
      get "/media", AdminController, :media
      patch "/media/:id", AdminController, :update_media
      delete "/media/:id", AdminController, :delete_media
      get "/rooms", AdminController, :rooms
      get "/jobs", AdminController, :jobs
      get "/metrics", AdminController, :metrics
    end
  end

  scope "/media", NobarSyncWeb do
    get "/t/:token/*path", MediaGatewayController, :show
  end
end
