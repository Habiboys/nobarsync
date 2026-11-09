defmodule NobarSync.Repo.Migrations.AccountLifecycle do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add(:status, :text, null: false, default: "active")
      add(:auth_version, :integer, null: false, default: 0)
    end

    create(constraint(:users, :users_status_valid, check: "status IN ('active', 'suspended')"))
    create(index(:users, [:status, :inserted_at]))
  end
end
