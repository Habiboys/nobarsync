defmodule NobarSync.Repo.Migrations.CreateCore do
  use Ecto.Migration

  def change do
    create table(:users, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :email, :string, null: false
      add :display_name, :string, null: false
      add :password_hash, :string, null: false
      add :role, :string, null: false, default: "user"
      add :avatar_key, :string
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:users, [:email])

    create table(:sessions, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
      add :token_hash, :binary, null: false
      add :csrf_token, :string, null: false
      add :expires_at, :utc_datetime_usec, null: false
      add :revoked_at, :utc_datetime_usec
      add :user_agent, :string
      add :ip, :string
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:sessions, [:token_hash])
    create index(:sessions, [:user_id])

    create table(:guest_identities, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :display_name, :string, null: false
      add :token_hash, :binary, null: false
      add :last_seen_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:guest_identities, [:token_hash])

    create table(:media_assets, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :owner_id, references(:users, type: :uuid, on_delete: :nilify_all)
      add :title, :string, null: false
      add :description, :text
      add :status, :string, null: false, default: "pending"
      add :source_type, :string, null: false
      add :provider, :string, null: false, default: "r2_hls"
      add :source_key, :string
      add :source_url, :string
      add :youtube_id, :string
      add :duration_ms, :bigint
      add :width, :integer
      add :height, :integer
      add :byte_size, :bigint
      add :content_type, :string
      add :checksum, :string
      add :poster_key, :string
      add :master_playlist_key, :string
      add :progress, :float, null: false, default: 0.0
      add :error, :text
      add :visibility, :string, null: false, default: "private"
      timestamps(type: :utc_datetime_usec)
    end

    create index(:media_assets, [:status])
    create index(:media_assets, [:owner_id])
    create index(:media_assets, [:inserted_at])

    create table(:media_variants, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :media_asset_id, references(:media_assets, type: :uuid, on_delete: :delete_all), null: false
      add :label, :string, null: false
      add :playlist_key, :string, null: false
      add :bandwidth, :integer, null: false
      add :width, :integer
      add :height, :integer
      add :codecs, :string
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:media_variants, [:media_asset_id, :label])

    create table(:media_subtitles, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :media_asset_id, references(:media_assets, type: :uuid, on_delete: :delete_all), null: false
      add :language, :string, null: false
      add :label, :string, null: false
      add :vtt_key, :string, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:media_subtitles, [:media_asset_id, :language])

    create table(:upload_sessions, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :owner_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
      add :media_asset_id, references(:media_assets, type: :uuid, on_delete: :delete_all), null: false
      add :object_key, :string, null: false
      add :upload_id, :string, null: false
      add :status, :string, null: false, default: "active"
      add :part_size, :integer, null: false
      add :bytes_expected, :bigint
      add :content_type, :string
      add :expires_at, :utc_datetime_usec, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create index(:upload_sessions, [:owner_id])
    create index(:upload_sessions, [:status])

    create table(:rooms, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :code, :string, null: false
      add :host_user_id, references(:users, type: :uuid, on_delete: :nilify_all)
      add :title, :string, null: false
      add :visibility, :string, null: false, default: "private"
      add :password_hash, :string
      add :expires_at, :utc_datetime_usec
      add :max_viewers, :integer, null: false, default: 50
      add :control_mode, :string, null: false, default: "host_only"
      add :buffering_mode, :string, null: false, default: "independent"
      add :chat_permission, :string, null: false, default: "everyone"
      add :host_transfer_policy, :string, null: false, default: "transfer"
      add :locked, :boolean, null: false, default: false
      add :status, :string, null: false, default: "open"
      add :media_asset_id, references(:media_assets, type: :uuid, on_delete: :nilify_all)
      add :empty_since, :utc_datetime_usec
      add :empty_ttl_seconds, :integer, null: false, default: 600
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:rooms, [:code])
    create index(:rooms, [:status])

    create table(:room_members, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :room_id, references(:rooms, type: :uuid, on_delete: :delete_all), null: false
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all)
      add :guest_identity_id, references(:guest_identities, type: :uuid, on_delete: :delete_all)
      add :role, :string, null: false, default: "viewer"
      add :display_name, :string, null: false
      add :banned, :boolean, null: false, default: false
      add :joined_at, :utc_datetime_usec, null: false
      add :left_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create index(:room_members, [:room_id, :inserted_at])
    create index(:room_members, [:user_id])

    create unique_index(:room_members, [:room_id, :user_id],
             where: "user_id IS NOT NULL AND left_at IS NULL",
             name: :room_members_active_user_index
           )

    create unique_index(:room_members, [:room_id, :guest_identity_id],
             where: "guest_identity_id IS NOT NULL AND left_at IS NULL",
             name: :room_members_active_guest_index
           )

    create constraint(:room_members, :room_member_one_identity,
             check: "(user_id IS NULL) <> (guest_identity_id IS NULL)"
           )

    create table(:invitations, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :room_id, references(:rooms, type: :uuid, on_delete: :delete_all), null: false
      add :code, :string, null: false
      add :created_by_id, references(:users, type: :uuid, on_delete: :nilify_all)
      add :expires_at, :utc_datetime_usec
      add :max_uses, :integer
      add :use_count, :integer, null: false, default: 0
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:invitations, [:code])

    create table(:playlist_items, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :room_id, references(:rooms, type: :uuid, on_delete: :delete_all), null: false
      add :media_asset_id, references(:media_assets, type: :uuid, on_delete: :delete_all), null: false
      add :position, :integer, null: false
      add :added_by_id, references(:users, type: :uuid, on_delete: :nilify_all)
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:playlist_items, [:room_id, :position])
    create index(:playlist_items, [:room_id, :inserted_at])

    create table(:playlist_votes, primary_key: false) do
      add :id, :uuid, primary_key: true

      add :playlist_item_id, references(:playlist_items, type: :uuid, on_delete: :delete_all),
        null: false

      add :room_member_id, references(:room_members, type: :uuid, on_delete: :delete_all),
        null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:playlist_votes, [:playlist_item_id, :room_member_id])

    create table(:room_playback_snapshots, primary_key: false) do
      add :room_id, references(:rooms, type: :uuid, on_delete: :delete_all), primary_key: true
      add :revision, :bigint, null: false, default: 0
      add :media_asset_id, references(:media_assets, type: :uuid, on_delete: :nilify_all)
      add :status, :string, null: false, default: "idle"
      add :anchor_position_ms, :bigint, null: false, default: 0
      add :anchor_wall_ms, :bigint, null: false, default: 0
      add :playback_rate, :float, null: false, default: 1.0
      add :effective_at_ms, :bigint
      add :duration_ms, :bigint, null: false, default: 0
      add :control_mode, :string, null: false, default: "host_only"
      add :buffering_mode, :string, null: false, default: "independent"
      timestamps(type: :utc_datetime_usec)
    end

    create table(:playback_events, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :room_id, references(:rooms, type: :uuid, on_delete: :delete_all), null: false
      add :revision, :bigint, null: false
      add :request_id, :string
      add :actor_member_id, references(:room_members, type: :uuid, on_delete: :nilify_all)
      add :type, :string, null: false
      add :payload, :map, null: false, default: %{}
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:playback_events, [:room_id, :inserted_at])

    create unique_index(:playback_events, [:room_id, :request_id],
             where: "request_id IS NOT NULL",
             name: :playback_events_request_index
           )

    create table(:room_messages, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :room_id, references(:rooms, type: :uuid, on_delete: :delete_all), null: false
      add :member_id, references(:room_members, type: :uuid, on_delete: :nilify_all)
      add :display_name, :string, null: false
      add :body, :text, null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:room_messages, [:room_id, :inserted_at])

    create table(:room_reactions, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :room_id, references(:rooms, type: :uuid, on_delete: :delete_all), null: false
      add :member_id, references(:room_members, type: :uuid, on_delete: :nilify_all)
      add :display_name, :string, null: false
      add :emoji, :string, null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:room_reactions, [:room_id, :inserted_at])

    create table(:room_ready_checks, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :room_id, references(:rooms, type: :uuid, on_delete: :delete_all), null: false
      add :member_id, references(:room_members, type: :uuid, on_delete: :delete_all), null: false
      add :ready, :boolean, null: false, default: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:room_ready_checks, [:room_id, :member_id])

    create table(:room_leases, primary_key: false) do
      add :room_id, references(:rooms, type: :uuid, on_delete: :delete_all), primary_key: true
      add :node_id, :string, null: false
      add :fencing_token, :bigint, null: false
      add :expires_at, :utc_datetime_usec, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create table(:audit_logs, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :actor_user_id, references(:users, type: :uuid, on_delete: :nilify_all)
      add :action, :string, null: false
      add :resource_type, :string
      add :resource_id, :string
      add :metadata, :map, null: false, default: %{}
      add :ip, :string
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:audit_logs, [:inserted_at])
    create index(:audit_logs, [:resource_type, :resource_id])
  end
end
