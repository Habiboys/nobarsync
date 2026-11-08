defmodule NobarSync.WatchRooms.Room do
  use NobarSync.Schema

  schema "rooms" do
    field :code, :string
    field :title, :string
    field :visibility, :string, default: "private"
    field :password, :string, virtual: true, redact: true
    field :password_hash, :string, redact: true
    field :expires_at, :utc_datetime_usec
    field :max_viewers, :integer, default: 50
    field :control_mode, :string, default: "host_only"
    field :buffering_mode, :string, default: "independent"
    field :chat_permission, :string, default: "everyone"
    field :host_transfer_policy, :string, default: "transfer"
    field :locked, :boolean, default: false
    field :status, :string, default: "open"
    field :empty_since, :utc_datetime_usec
    field :empty_ttl_seconds, :integer, default: 600
    belongs_to :host_user, NobarSync.Accounts.User
    belongs_to :media_asset, NobarSync.Media.Asset
    has_many :members, NobarSync.WatchRooms.Member
    has_many :playlist_items, NobarSync.WatchRooms.PlaylistItem
    timestamps()
  end

  def changeset(room, attrs) do
    room
    |> cast(attrs, [
      :title,
      :visibility,
      :password,
      :expires_at,
      :max_viewers,
      :control_mode,
      :buffering_mode,
      :chat_permission,
      :host_transfer_policy,
      :locked,
      :empty_ttl_seconds,
      :media_asset_id
    ])
    |> validate_required([:title])
    |> validate_length(:title, min: 2, max: 80)
    |> validate_inclusion(:visibility, ~w(public private password))
    |> validate_inclusion(:control_mode, ~w(host_only everyone))
    |> validate_inclusion(:buffering_mode, ~w(independent pause_all host_decides))
    |> validate_inclusion(:chat_permission, ~w(everyone host_mod off))
    |> validate_inclusion(:host_transfer_policy, ~w(transfer close))
    |> validate_number(:max_viewers, greater_than: 0, less_than_or_equal_to: 1000)
    |> hash_password()
  end

  defp hash_password(changeset) do
    case get_change(changeset, :password) do
      nil -> changeset
      password -> put_change(changeset, :password_hash, Bcrypt.hash_pwd_salt(password))
    end
  end
end
