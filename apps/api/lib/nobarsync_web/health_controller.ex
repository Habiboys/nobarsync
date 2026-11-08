defmodule NobarSyncWeb.HealthController do
  use NobarSyncWeb, :controller

  def live(conn, _), do: json(conn, %{status: "ok"})

  def ready(conn, _) do
    Ecto.Adapters.SQL.query!(NobarSync.Repo, "SELECT 1")
    json(conn, %{status: "ok"})
  rescue
    _ -> conn |> put_status(503) |> json(%{status: "degraded"})
  end

  def summary(conn, _), do: ready(conn, %{})
end
