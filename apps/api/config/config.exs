import Config

config :nobarsync,
  ecto_repos: [NobarSync.Repo],
  generators: [timestamp_type: :utc_datetime_usec, binary_id: true]

config :nobarsync, NobarSyncWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [formats: [json: NobarSyncWeb.ErrorJSON], layout: false],
  pubsub_server: NobarSync.PubSub,
  live_view: [signing_salt: "nobarsync-live"]

config :nobarsync, Oban,
  repo: NobarSync.Repo,
  queues: [encode: 1, maintenance: 1],
  plugins: [
    {Oban.Plugins.Pruner, max_age: 86_400},
    {Oban.Plugins.Cron, crontab: [{"* * * * *", NobarSync.WatchRooms.CloseEmptyRoomsWorker}]}
  ]

config :ex_aws,
  json_codec: Jason,
  access_key_id: "nobarsync",
  secret_access_key: "nobarsync-secret",
  region: "us-east-1"

config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :room_id]

config :phoenix, :json_library, Jason

config :bcrypt_elixir, log_rounds: 12

import_config "#{config_env()}.exs"
