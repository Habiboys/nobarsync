defmodule NobarSync.Messaging.Message do
  use NobarSync.Schema

  schema "room_messages" do
    field :display_name, :string
    field :body, :string
    field :edited_at, :utc_datetime_usec
    field :deleted_at, :utc_datetime_usec
    field :pinned_at, :utc_datetime_usec
    belongs_to :room, NobarSync.WatchRooms.Room
    belongs_to :member, NobarSync.WatchRooms.Member
    belongs_to :reply_to, __MODULE__
    belongs_to :pinned_by_member, NobarSync.WatchRooms.Member
    has_many :message_reactions, NobarSync.Messaging.MessageReaction, foreign_key: :message_id
    timestamps(updated_at: false)
  end
end
