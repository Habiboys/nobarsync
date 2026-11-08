defmodule NobarSync.WatchRooms.Invitation do
  use NobarSync.Schema

  schema "invitations" do
    field :code, :string
    field :expires_at, :utc_datetime_usec
    field :max_uses, :integer
    field :use_count, :integer, default: 0
    belongs_to :room, NobarSync.WatchRooms.Room
    belongs_to :created_by, NobarSync.Accounts.User
    timestamps()
  end
end
