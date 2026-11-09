defmodule NobarSyncWeb.AdminController do
  use NobarSyncWeb, :controller

  import Ecto.Query
  alias NobarSync.{Repo, WatchRooms}
  alias NobarSync.Media.Asset

  def users(conn, params) do
    result = NobarSync.AdminAccounts.list(params)
    json(conn, %{result | users: Enum.map(result.users, &user_json/1)})
  end

  def update_user(conn, %{"id" => id} = params) do
    with {:ok, user} <- NobarSync.AdminAccounts.update(conn.assigns.current_user, id, params) do
      json(conn, %{user: user_json(user)})
    end
  end

  def revoke_sessions(conn, %{"id" => id} = params) do
    with {:ok, user} <-
           NobarSync.AdminAccounts.update(conn.assigns.current_user, id, params, true) do
      json(conn, %{user: user_json(user)})
    end
  end

  def audit(conn, _), do: json(conn, %{events: NobarSync.AdminAccounts.audit()})

  defp user_json(user),
    do: Map.merge(NobarSyncWeb.AuthController.user_json(user), %{inserted_at: user.inserted_at})

  def media(conn, params) do
    result = NobarSync.AdminMedia.list(params)
    json(conn, %{result | items: Enum.map(result.items, &admin_media_json/1)})
  end

  def update_media(conn, %{"id" => id} = params) do
    with {:ok, asset} <- NobarSync.AdminMedia.update(conn.assigns.current_user, id, params) do
      json(conn, %{media: admin_media_json(asset)})
    end
  end

  def delete_media(conn, %{"id" => id} = params) do
    with {:ok, _} <- NobarSync.AdminMedia.delete(conn.assigns.current_user, id, params) do
      json(conn, %{ok: true})
    end
  end

  defp admin_media_json(asset) do
    Map.put(
      NobarSyncWeb.MediaController.asset_json(asset),
      :owner,
      asset.owner &&
        %{id: asset.owner.id, display_name: asset.owner.display_name, email: asset.owner.email}
    )
    |> Map.merge(%{
      byte_size: asset.byte_size,
      content_type: asset.content_type,
      inserted_at: asset.inserted_at,
      updated_at: asset.updated_at
    })
  end

  def rooms(conn, _) do
    json(conn, %{
      rooms: Enum.map(WatchRooms.list_open_rooms(), &NobarSyncWeb.RoomController.room_json/1)
    })
  end

  def jobs(conn, _) do
    jobs =
      Repo.all(from j in Oban.Job, order_by: [desc: j.id], limit: 50)
      |> Enum.map(
        &%{id: &1.id, worker: &1.worker, state: &1.state, queue: &1.queue, attempt: &1.attempt}
      )

    json(conn, %{jobs: jobs})
  end

  def metrics(conn, _) do
    counts = %{
      users: Repo.aggregate(NobarSync.Accounts.User, :count),
      media: Repo.aggregate(Asset, :count),
      ready_media: Repo.aggregate(from(a in Asset, where: a.status == "ready"), :count),
      open_rooms:
        Repo.aggregate(from(r in NobarSync.WatchRooms.Room, where: r.status == "open"), :count)
    }

    json(conn, %{counts: counts, sync: NobarSync.Analytics.Metrics.snapshot()})
  end
end
