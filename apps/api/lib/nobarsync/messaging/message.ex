defmodule NobarSync.Messaging.Message do
  use NobarSync.Schema

  schema "room_messages" do
    field :display_name, :string
    field :body, :string
    belongs_to :room, NobarSync.WatchRooms.Room
    belongs_to :member, NobarSync.WatchRooms.Member
    timestamps(updated_at: false)
  end
end
