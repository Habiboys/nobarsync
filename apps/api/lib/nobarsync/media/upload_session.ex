defmodule NobarSync.Media.UploadSession do
  use NobarSync.Schema

  schema "upload_sessions" do
    field :object_key, :string
    field :upload_id, :string
    field :status, :string, default: "active"
    field :part_size, :integer
    field :bytes_expected, :integer
    field :content_type, :string
    field :expires_at, :utc_datetime_usec
    belongs_to :owner, NobarSync.Accounts.User
    belongs_to :media_asset, NobarSync.Media.Asset
    timestamps()
  end
end
