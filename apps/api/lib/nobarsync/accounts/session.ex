defmodule NobarSync.Accounts.Session do
  use NobarSync.Schema

  schema "sessions" do
    field :token_hash, :binary, redact: true
    field :csrf_token, :string, redact: true
    field :expires_at, :utc_datetime_usec
    field :revoked_at, :utc_datetime_usec
    field :user_agent, :string
    field :ip, :string
    belongs_to :user, NobarSync.Accounts.User
    timestamps()
  end
end
