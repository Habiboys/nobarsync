import Config

role = System.get_env("NOBARSYNC_ROLE") || "all"
config :nobarsync, :role, role

if config_env() == :prod do
  required = [
    "SECRET_KEY_BASE",
    "DATABASE_URL",
    "MEDIA_TOKEN_SECRET",
    "S3_ACCESS_KEY",
    "S3_SECRET_KEY",
    "S3_BUCKET"
  ]

  missing = Enum.filter(required, &(System.get_env(&1) in [nil, ""]))
  if missing != [], do: raise("Missing production environment: #{Enum.join(missing, ", ")}")

  host = System.get_env("PHX_HOST") || "localhost"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :nobarsync, NobarSyncWeb.Endpoint,
    url: [host: host, port: 80, scheme: System.get_env("PHX_SCHEME") || "http"],
    http: [ip: {0, 0, 0, 0}, port: port],
    secret_key_base: System.fetch_env!("SECRET_KEY_BASE")

  config :nobarsync, NobarSync.Repo,
    url: System.fetch_env!("DATABASE_URL"),
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")

  config :nobarsync,
    media_token_secret: System.fetch_env!("MEDIA_TOKEN_SECRET"),
    force_secure_cookies: (System.get_env("FORCE_SECURE_COOKIES") || "true") == "true",
    web_origin: System.get_env("WEB_ORIGIN") || "http://#{host}"

  config :logger, :default_formatter, format: {NobarSync.LoggerJSON, :format}
end

if config_env() != :test do
  encode_concurrency = String.to_integer(System.get_env("ENCODE_CONCURRENCY") || "1")

  queues =
    case role do
      "worker" -> [encode: encode_concurrency]
      "api" -> [maintenance: 1]
      _ -> [encode: encode_concurrency, maintenance: 1]
    end

  plugins =
    [{Oban.Plugins.Pruner, max_age: 86_400}, {Oban.Plugins.Lifeline, rescue_after: :timer.minutes(5)}] ++
      if role in ["api", "all"] do
        [
          {Oban.Plugins.Cron,
           crontab: [{"* * * * *", NobarSync.WatchRooms.CloseEmptyRoomsWorker}]}
        ]
      else
        []
      end

  config :nobarsync, Oban, queues: queues, plugins: plugins
end
