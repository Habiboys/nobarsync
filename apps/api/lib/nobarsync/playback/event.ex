defmodule NobarSync.Playback.Event do
  use NobarSync.Schema

  schema "playback_events" do
    field :revision, :integer
    field :request_id, :string
    field :type, :string
    field :payload, :map, default: %{}
    belongs_to :room, NobarSync.WatchRooms.Room
    belongs_to :actor_member, NobarSync.WatchRooms.Member, foreign_key: :actor_member_id
    timestamps(updated_at: false)
  end
end
