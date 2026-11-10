defmodule NobarSync.Repo.Migrations.MediaShareReview do
  use Ecto.Migration

  def change do
    alter table(:media_assets) do
      add(:share_request, :string, null: false, default: "none")
      add(:share_note, :text)
      add(:reviewed_at, :utc_datetime_usec)
    end

    create(
      constraint(:media_assets, :media_assets_share_request_valid,
        check: "share_request IN ('none', 'pending', 'approved', 'rejected')"
      )
    )

    create(index(:media_assets, [:share_request, :inserted_at]))
  end
end
