import Config

config :nobarsync, NobarSync.Repo,
  username: System.get_env("POSTGRES_USER", "nobarsync"),
  password: System.get_env("POSTGRES_PASSWORD", "nobarsync"),
  hostname: System.get_env("POSTGRES_HOST", "localhost"),
  database: System.get_env("POSTGRES_DB", "nobarsync_test"),
  port: String.to_integer(System.get_env("POSTGRES_PORT", "5432")),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

config :nobarsync, NobarSyncWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "test-only-secret-key-base-0123456789abcdef0123456789abcdef",
  server: false

config :nobarsync, Oban, testing: :manual, queues: false, plugins: false

config :nobarsync,
  media_token_secret: "test-secret",
  force_secure_cookies: false,
  web_origin: "http://localhost:5173",
  sql_sandbox: true

config :bcrypt_elixir, log_rounds: 4
config :logger, level: :warning
config :phoenix, :plug_init_mode, :runtime
