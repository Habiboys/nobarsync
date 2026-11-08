defmodule NobarSync.Media.Variant do
  use NobarSync.Schema

  schema "media_variants" do
    field :label, :string
    field :playlist_key, :string
    field :bandwidth, :integer
    field :width, :integer
    field :height, :integer
    field :codecs, :string
    belongs_to :media_asset, NobarSync.Media.Asset
    timestamps()
  end
end
