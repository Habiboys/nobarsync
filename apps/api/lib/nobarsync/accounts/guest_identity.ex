defmodule NobarSync.Accounts.GuestIdentity do
  use NobarSync.Schema

  schema "guest_identities" do
    field :display_name, :string
    field :token_hash, :binary, redact: true
    field :last_seen_at, :utc_datetime_usec
    timestamps()
  end
end
