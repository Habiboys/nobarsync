defmodule NobarSync.WatchRooms.PlaylistItem do
  use NobarSync.Schema

  schema "playlist_items" do
    field :position, :integer
    belongs_to :room, NobarSync.WatchRooms.Room
    belongs_to :media_asset, NobarSync.Media.Asset
    belongs_to :added_by, NobarSync.Accounts.User
    has_many :votes, NobarSync.WatchRooms.PlaylistVote
    timestamps()
  end

  def changeset(item, attrs) do
    item
    |> cast(attrs, [:room_id, :media_asset_id, :added_by_id, :position])
    |> validate_required([:room_id, :media_asset_id, :position])
    |> validate_number(:position, greater_than: 0)
    |> foreign_key_constraint(:room_id)
    |> foreign_key_constraint(:media_asset_id)
    |> foreign_key_constraint(:added_by_id)
    |> unique_constraint([:room_id, :position])
  end
end
