defmodule NobarSync.Media.Asset do
  use NobarSync.Schema

  schema "media_assets" do
    field :title, :string
    field :description, :string
    field :status, :string, default: "pending"
    field :source_type, :string
    field :provider, :string, default: "r2_hls"
    field :source_key, :string
    field :source_url, :string
    field :youtube_id, :string
    field :duration_ms, :integer
    field :width, :integer
    field :height, :integer
    field :byte_size, :integer
    field :content_type, :string
    field :checksum, :string
    field :poster_key, :string
    field :master_playlist_key, :string
    field :progress, :float, default: 0.0
    field :error, :string
    field :visibility, :string, default: "private"
    field :share_request, :string, default: "none"
    field :share_note, :string
    field :reviewed_at, :utc_datetime_usec
    belongs_to :owner, NobarSync.Accounts.User
    has_many :variants, NobarSync.Media.Variant, foreign_key: :media_asset_id
    has_many :subtitles, NobarSync.Media.Subtitle, foreign_key: :media_asset_id
    timestamps()
  end

  def changeset(asset, attrs) do
    asset
    |> cast(attrs, [
      :owner_id,
      :title,
      :description,
      :status,
      :source_type,
      :provider,
      :source_key,
      :source_url,
      :youtube_id,
      :duration_ms,
      :width,
      :height,
      :byte_size,
      :content_type,
      :checksum,
      :poster_key,
      :master_playlist_key,
      :progress,
      :error,
      :visibility,
      :share_request,
      :share_note,
      :reviewed_at
    ])
    |> validate_required([:title, :status, :source_type, :provider])
    |> validate_inclusion(
      :status,
      ~w(pending queued probing processing uploading ready failed cancelled)
    )
    |> validate_inclusion(:visibility, ~w(private library))
    |> validate_inclusion(:share_request, ~w(none pending approved rejected))
    |> validate_length(:title, min: 1, max: 160)
    |> validate_length(:share_note, max: 500)
  end
end
