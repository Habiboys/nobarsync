defmodule NobarSync.Messaging.MessageReaction do
  use NobarSync.Schema

  schema "room_message_reactions" do
    field :emoji, :string
    belongs_to :room, NobarSync.WatchRooms.Room
    belongs_to :message, NobarSync.Messaging.Message
    belongs_to :member, NobarSync.WatchRooms.Member
    timestamps(updated_at: false)
  end
end
