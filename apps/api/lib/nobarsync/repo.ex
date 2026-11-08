defmodule NobarSync.Repo do
  use Ecto.Repo,
    otp_app: :nobarsync,
    adapter: Ecto.Adapters.Postgres
end
