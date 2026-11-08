defmodule NobarSync.Repo.Migrations.WidenUploadId do
  use Ecto.Migration

  def change do
    alter table(:upload_sessions) do
      modify :upload_id, :text, null: false
    end
  end
end
