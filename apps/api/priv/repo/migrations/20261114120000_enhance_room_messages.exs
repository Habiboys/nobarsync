defmodule NobarSync.Repo.Migrations.EnhanceRoomMessages do
  use Ecto.Migration

  def change do
    alter table(:room_messages) do
      add :reply_to_id, references(:room_messages, type: :uuid, on_delete: :nilify_all)
      add :edited_at, :utc_datetime_usec
      add :deleted_at, :utc_datetime_usec
      add :pinned_at, :utc_datetime_usec
      add :pinned_by_member_id, references(:room_members, type: :uuid, on_delete: :nilify_all)
    end

    create index(:room_messages, [:room_id, :deleted_at, :inserted_at])
    create index(:room_messages, [:room_id, :pinned_at])

    create table(:room_message_reactions, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :room_id, references(:rooms, type: :uuid, on_delete: :delete_all), null: false
      add :message_id, references(:room_messages, type: :uuid, on_delete: :delete_all), null: false
      add :member_id, references(:room_members, type: :uuid, on_delete: :delete_all), null: false
      add :emoji, :string, null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:room_message_reactions, [:message_id, :member_id, :emoji])
    create index(:room_message_reactions, [:room_id, :message_id])
  end
end
