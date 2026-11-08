defmodule NobarSync.Audit.Log do
  use NobarSync.Schema

  @timestamps_opts [type: :utc_datetime_usec, inserted_at: :inserted_at, updated_at: false]
  schema "audit_logs" do
    field :action, :string
    field :resource_type, :string
    field :resource_id, :string
    field :metadata, :map, default: %{}
    field :ip, :string
    belongs_to :actor_user, NobarSync.Accounts.User, foreign_key: :actor_user_id
    timestamps(updated_at: false)
  end
end
