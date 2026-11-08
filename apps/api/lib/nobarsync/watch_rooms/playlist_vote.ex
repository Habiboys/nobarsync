defmodule NobarSync.WatchRooms.PlaylistVote do
  use NobarSync.Schema

  schema "playlist_votes" do
    belongs_to :playlist_item, NobarSync.WatchRooms.PlaylistItem
    belongs_to :room_member, NobarSync.WatchRooms.Member
    timestamps()
  end
end
