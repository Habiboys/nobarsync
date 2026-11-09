defmodule NobarSync.AdminMediaTest do
  use NobarSync.DataCase, async: false
  alias NobarSync.{Accounts, AdminAccounts, AdminMedia, Media}

  setup do
    make = fn name ->
      {:ok, user} =
        Accounts.register_user(%{
          "email" => "#{name}-#{System.unique_integer([:positive])}@example.com",
          "display_name" => name,
          "password" => "password123"
        })

      user
    end

    {:ok, admin} = Accounts.promote_admin(make.("Admin"))
    owner = make.("Owner")

    {:ok, asset} =
      Media.create_youtube(owner, %{"url" => "https://youtu.be/dQw4w9WgXcQ", "title" => "Film pribadi"})

    %{admin: admin, owner: owner, asset: asset}
  end

  test "lists private films from every owner with owner details", %{owner: owner, asset: asset} do
    assert asset.visibility == "private"
    result = AdminMedia.list(%{"search" => owner.email, "visibility" => "private"})
    assert [%{id: id, owner: listed_owner}] = result.items
    assert id == asset.id and listed_owner.id == owner.id
    assert AdminMedia.list(%{"search" => "tidak-ada-film"}).total == 0
    assert AdminMedia.list(%{"search" => %{}, "page" => %{}}).page == 1
  end

  test "updates another user's film with a reason and records the audit", %{
    admin: admin,
    asset: asset
  } do
    assert {:ok, updated} =
             AdminMedia.update(admin, asset.id, %{
               "title" => "Judul baru",
               "visibility" => "library",
               "reason" => "Judul melanggar aturan"
             })

    assert updated.title == "Judul baru" and updated.visibility == "library"
    assert [%{action: "admin.media_update", metadata: metadata}] = AdminAccounts.audit()
    assert metadata["reason"] == "Judul melanggar aturan"
    assert metadata["before"]["title"] == "Film pribadi"
    assert metadata["after"]["title"] == "Judul baru"
  end

  test "rejects missing reasons, non-admins and invalid changes without auditing", %{
    admin: admin,
    owner: owner,
    asset: asset
  } do
    assert {:error, {:invalid, _}} = AdminMedia.update(admin, asset.id, %{"title" => "Tanpa alasan"})
    assert {:error, {:invalid, _}} = AdminMedia.delete(admin, asset.id, %{"reason" => " "})

    assert {:error, :forbidden} =
             AdminMedia.delete(owner, asset.id, %{"reason" => "Bukan admin"})

    assert {:error, :not_found} = AdminMedia.update(admin, "bukan-uuid", %{"reason" => "Uji id"})

    assert {:error, %Ecto.Changeset{}} =
             AdminMedia.update(admin, asset.id, %{"visibility" => "public", "reason" => "Akses salah"})

    assert NobarSync.Repo.get!(NobarSync.Media.Asset, asset.id).title == "Film pribadi"
    assert AdminAccounts.audit() == []
  end
end
