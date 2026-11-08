defmodule NobarSyncWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :nobarsync

  socket "/socket", NobarSyncWeb.UserSocket, websocket: true, longpoll: false

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug CORSPlug,
    origin: &NobarSyncWeb.CORS.origin/1,
    credentials: true,
    headers: ["content-type", "x-nobarsync-csrf", "authorization"],
    methods: ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS", "HEAD"],
    max_age: 86400

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library(),
    length: 2_000_000

  plug Plug.MethodOverride
  plug Plug.Head
  plug NobarSyncWeb.Router
end
