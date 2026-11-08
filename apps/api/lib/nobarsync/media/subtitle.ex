defmodule NobarSync.Media.Subtitle do
  use NobarSync.Schema

  schema "media_subtitles" do
    field :language, :string
    field :label, :string
    field :vtt_key, :string
    belongs_to :media_asset, NobarSync.Media.Asset
    timestamps()
  end
end
