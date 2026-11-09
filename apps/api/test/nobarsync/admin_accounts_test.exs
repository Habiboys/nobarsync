defmodule NobarSync.AdminAccountsTest do
  use NobarSync.DataCase, async: false
  alias NobarSync.{Accounts, AdminAccounts, Repo}
  alias NobarSyncWeb.UserSocket

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
    %{admin: admin, user: make.("Member")}
  end

  test "suspension revokes sessions, disconnects sockets and invalidates signed tokens", %{
    admin: admin,
    user: user
  } do
    {:ok, session} = Accounts.create_session(user, %{})
    token = Phoenix.Token.sign(NobarSyncWeb.Endpoint, "socket", Accounts.socket_claims(user))
    assert {:ok, _} = UserSocket.connect(%{"token" => token}, %Phoenix.Socket{}, %{})
    NobarSyncWeb.Endpoint.subscribe("socket:#{user.id}")

    assert {:ok, %{status: "suspended"}} =
             AdminAccounts.update(admin, user.id, %{
               "status" => "suspended",
               "reason" => "Pelanggaran uji"
             })

    assert_receive %Phoenix.Socket.Broadcast{event: "disconnect"}
    assert is_nil(Accounts.get_session_by_token(session.token))
    assert {:error, :account_suspended} = Accounts.authenticate(user.email, "password123")
    assert {:error, :account_suspended} = Accounts.create_session(user, %{})
    assert :error = UserSocket.connect(%{"token" => token}, %Phoenix.Socket{}, %{})

    assert {:ok, %{status: "active"}} =
             AdminAccounts.update(admin, user.id, %{
               "status" => "active",
               "reason" => "Aktivasi uji"
             })

    assert {:ok, _} = Accounts.authenticate(user.email, "password123")
    assert is_nil(Accounts.get_session_by_token(session.token))
    assert :error = UserSocket.connect(%{"token" => token}, %Phoenix.Socket{}, %{})
    assert length(AdminAccounts.audit()) == 2
  end

  test "revoking sessions requires login again and invalidates old socket tokens", %{
    admin: admin,
    user: user
  } do
    {:ok, session} = Accounts.create_session(user, %{})

    assert {:ok, updated} =
             AdminAccounts.update(admin, user.id, %{"reason" => "Akhiri semua sesi"}, true)

    assert updated.auth_version == user.auth_version + 1
    assert updated.status == "active"
    assert is_nil(Accounts.get_session_by_token(session.token))
    assert {:ok, _} = Accounts.create_session(updated, %{})
  end

  test "self-demotion, self-suspension and forged admin access are rejected", %{
    admin: admin,
    user: user
  } do
    for attrs <- [%{"role" => "user"}, %{"status" => "suspended"}] do
      assert {:error, {:invalid, _}} =
               AdminAccounts.update(admin, admin.id, Map.put(attrs, "reason", "Uji perlindungan"))
    end

    assert {:error, :forbidden} =
             AdminAccounts.update(user, admin.id, %{
               "status" => "suspended",
               "reason" => "Tidak berhak"
             })

    Repo.update!(Ecto.Changeset.change(admin, role: "user"))

    assert {:error, :forbidden} =
             AdminAccounts.update(admin, user.id, %{
               "status" => "suspended",
               "reason" => "Admin lama"
             })

    assert AdminAccounts.audit() == []
  end

  test "registration cannot set admin role or suspended state and malformed changes are atomic",
       %{admin: admin, user: user} do
    assert {:ok, registered} =
             Accounts.register_user(%{
               "email" => "forged-#{System.unique_integer([:positive])}@example.com",
               "display_name" => "New user",
               "password" => "password123",
               "role" => "admin",
               "status" => "suspended"
             })

    assert registered.role == "user" and registered.status == "active"

    assert {:error, %Ecto.Changeset{}} =
             AdminAccounts.update(admin, user.id, %{
               "role" => "owner",
               "reason" => "Peran tidak valid"
             })

    assert Accounts.get_user!(user.id).role == "user"
    assert AdminAccounts.audit() == []
    result = AdminAccounts.list(%{"search" => user.email, "page" => "1", "status" => "active"})
    assert result.total == 1
    assert Enum.map(result.users, & &1.id) == [user.id]
    assert AdminAccounts.list(%{"search" => %{}, "page" => %{}}).page == 1
  end
end
