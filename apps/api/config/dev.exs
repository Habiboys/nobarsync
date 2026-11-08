import Config

config :nobarsync, NobarSyncWeb.Endpoint,
  http: [ip: {0, 0, 0, 0}, port: String.to_integer(System.get_env("PORT", "4000"))],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base:
    System.get_env(
      "SECRET_KEY_BASE",
      "dev-only-secret-key-base-change-me-please-0123456789abcdef"
    ),
  watchers: []

config :nobarsync, NobarSync.Repo,
  username: System.get_env("POSTGRES_USER", "nobarsync"),
  password: System.get_env("POSTGRES_PASSWORD", "nobarsync"),
  hostname: System.get_env("POSTGRES_HOST", "localhost"),
  database: System.get_env("POSTGRES_DB", "nobarsync"),
  port: String.to_integer(System.get_env("POSTGRES_PORT", "5432")),
  pool_size: 10,
  stacktrace: true,
  show_sensitive_data_on_connection_error: true

config :nobarsync,
  media_token_secret:
    System.get_env("MEDIA_TOKEN_SECRET", "dev-only-media-token-secret-change-me"),
  force_secure_cookies: false,
  web_origin: System.get_env("WEB_ORIGIN", "http://localhost:5173"),
  dev_routes: true

config :logger, :default_formatter, format: "[$level] $message\n"

config :phoenix, :stacktrace_depth, 20
config :phoenix, :plug_init_mode, :runtime
