defmodule NobarSync.Messaging.Reaction do
  use NobarSync.Schema

  schema "room_reactions" do
    field :display_name, :string
    field :emoji, :string
    belongs_to :room, NobarSync.WatchRooms.Room
    belongs_to :member, NobarSync.WatchRooms.Member
    timestamps(updated_at: false)
  end
end
