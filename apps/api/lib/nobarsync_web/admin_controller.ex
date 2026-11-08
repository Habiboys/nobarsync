defmodule NobarSyncWeb.AdminController do
  use NobarSyncWeb, :controller

  import Ecto.Query
  alias NobarSync.{Accounts, Repo, WatchRooms}
  alias NobarSync.Media.Asset

  def users(conn, _),
    do:
      json(conn, %{
        users: Enum.map(Accounts.list_users(), &NobarSyncWeb.AuthController.user_json/1)
      })

  def media(conn, params), do: NobarSyncWeb.MediaController.index(conn, params)

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
