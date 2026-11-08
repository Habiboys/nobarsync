defmodule NobarSync.Playback.Snapshot do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:room_id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id
  schema "room_playback_snapshots" do
    field :revision, :integer, default: 0
    field :status, :string, default: "idle"
    field :anchor_position_ms, :integer, default: 0
    field :anchor_wall_ms, :integer, default: 0
    field :playback_rate, :float, default: 1.0
    field :effective_at_ms, :integer
    field :duration_ms, :integer, default: 0
    field :control_mode, :string, default: "host_only"
    field :buffering_mode, :string, default: "independent"
    belongs_to :media_asset, NobarSync.Media.Asset, foreign_key: :media_asset_id
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(snapshot, attrs) do
    snapshot
    |> cast(attrs, [
      :room_id,
      :revision,
      :media_asset_id,
      :status,
      :anchor_position_ms,
      :anchor_wall_ms,
      :playback_rate,
      :effective_at_ms,
      :duration_ms,
      :control_mode,
      :buffering_mode
    ])
    |> validate_required([:room_id, :revision, :status])
  end
end
