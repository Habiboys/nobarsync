defmodule NobarSync.AdminMedia do
  import Ecto.Query
  alias NobarSync.{Audit, Media, Repo}
  alias NobarSync.Accounts.User
  alias NobarSync.Media.Asset

  @per_page 20

  def list(params) do
    page = integer(params["page"], 1, 1_000_000)
    search = text(params["search"], 120)

    query = from(a in Asset, as: :asset, left_join: o in assoc(a, :owner), as: :owner)

    query =
      if search == "",
        do: query,
        else:
          where(
            query,
            [asset: a, owner: o],
            ilike(a.title, ^like(search)) or ilike(o.email, ^like(search)) or
              ilike(o.display_name, ^like(search))
          )

    query =
      if params["status"] in ~w(pending queued probing processing uploading ready failed cancelled),
        do: where(query, [asset: a], a.status == ^params["status"]),
        else: query

    query =
      if params["visibility"] in ~w(private library),
        do: where(query, [asset: a], a.visibility == ^params["visibility"]),
        else: query

    %{
      items:
        Repo.all(
          from [asset: a] in query,
            order_by: [desc: a.inserted_at, asc: a.id],
            limit: @per_page,
            offset: ^((page - 1) * @per_page),
            preload: [:owner, :variants, :subtitles]
        ),
      total: Repo.aggregate(query, :count),
      page: page,
      per_page: @per_page
    }
  end

  def update(actor, id, attrs) do
    with {:ok, reason} <- reason(attrs),
         {:ok, asset} <- fetch(actor, id) do
      Repo.transaction(fn ->
        updated =
          case Media.update_asset(asset, attrs) do
            {:ok, updated} -> updated
            {:error, error} -> Repo.rollback(error)
          end

        record!("admin.media_update", actor, asset, reason, %{
          before: snapshot(asset),
          after: snapshot(updated)
        })

        Repo.preload(updated, [:owner, :variants, :subtitles], force: true)
      end)
    end
  end

  # Storage deletion cannot roll back, so the audit row is written only after it succeeds.
  def delete(actor, id, attrs) do
    with {:ok, reason} <- reason(attrs),
         {:ok, asset} <- fetch(actor, id),
         {:ok, _} <- Media.delete_asset(asset) do
      record!("admin.media_delete", actor, asset, reason, %{before: snapshot(asset)})
      {:ok, asset}
    end
  end

  defp fetch(%User{role: "admin", status: "active"}, id) do
    with {:ok, uuid} <- Ecto.UUID.cast(id),
         %Asset{} = asset <- Repo.get(Asset, uuid) do
      {:ok, Repo.preload(asset, [:owner, :variants, :subtitles])}
    else
      _ -> {:error, :not_found}
    end
  end

  defp fetch(_, _), do: {:error, :forbidden}

  defp record!(action, actor, asset, reason, changes) do
    metadata =
      Map.merge(changes, %{
        reason: reason,
        owner: asset.owner && %{id: asset.owner.id, display_name: asset.owner.display_name, email: asset.owner.email}
      })

    {:ok, _} =
      Audit.log(action,
        actor_id: actor.id,
        resource_type: "media",
        resource_id: asset.id,
        metadata: metadata
      )
  end

  defp snapshot(asset), do: Map.take(asset, [:title, :description, :visibility, :status])

  defp reason(attrs) do
    reason = text(attrs["reason"], 501)

    if String.length(reason) in 3..500,
      do: {:ok, reason},
      else: {:error, {:invalid, "Alasan tindakan wajib diisi (3–500 karakter)."}}
  end

  defp text(value, max) when is_binary(value), do: value |> String.trim() |> String.slice(0, max)
  defp text(_, _), do: ""

  defp like(text) do
    escaped =
      text
      |> String.replace("\\", "\\\\")
      |> String.replace("%", "\\%")
      |> String.replace("_", "\\_")

    "%" <> escaped <> "%"
  end

  defp integer(value, default, max) when is_binary(value) or is_integer(value) or is_nil(value) do
    case Integer.parse(to_string(value || "")) do
      {n, ""} when n > 0 -> min(n, max)
      _ -> default
    end
  end

  defp integer(_, default, _), do: default
end
