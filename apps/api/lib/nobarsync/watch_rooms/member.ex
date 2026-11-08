defmodule NobarSync.WatchRooms.Member do
  use NobarSync.Schema

  schema "room_members" do
    field :role, :string, default: "viewer"
    field :display_name, :string
    field :banned, :boolean, default: false
    field :joined_at, :utc_datetime_usec
    field :left_at, :utc_datetime_usec
    belongs_to :room, NobarSync.WatchRooms.Room
    belongs_to :user, NobarSync.Accounts.User
    belongs_to :guest_identity, NobarSync.Accounts.GuestIdentity
    timestamps()
  end
end
