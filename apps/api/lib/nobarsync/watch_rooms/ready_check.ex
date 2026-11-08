defmodule NobarSync.WatchRooms.ReadyCheck do
  use NobarSync.Schema

  schema "room_ready_checks" do
    field :ready, :boolean, default: false
    belongs_to :room, NobarSync.WatchRooms.Room
    belongs_to :member, NobarSync.WatchRooms.Member
    timestamps()
  end
end
