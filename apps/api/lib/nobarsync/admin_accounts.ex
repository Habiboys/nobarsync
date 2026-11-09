defmodule NobarSync.AdminAccounts do
  import Ecto.Query
  alias NobarSync.{Audit, Repo}
  alias NobarSync.Accounts.{Session, User}

  def list(params) do
    page = integer(params["page"], 1, 1_000_000)

    search =
      String.slice(
        String.trim(if(is_binary(params["search"]), do: params["search"], else: "")),
        0,
        120
      )

    query = from(u in User)

    query =
      if search == "",
        do: query,
        else:
          where(
            query,
            [u],
            ilike(u.email, ^("%" <> escape(search) <> "%")) or
              ilike(u.display_name, ^("%" <> escape(search) <> "%"))
          )

    query =
      if params["status"] in ~w(active suspended),
        do: where(query, [u], u.status == ^params["status"]),
        else: query

    query =
      if params["role"] in ~w(user admin),
        do: where(query, [u], u.role == ^params["role"]),
        else: query

    %{
      users:
        Repo.all(
          from u in query,
            order_by: [desc: u.inserted_at, asc: u.id],
            limit: 20,
            offset: ^((page - 1) * 20)
        ),
      total: Repo.aggregate(query, :count),
      page: page,
      per_page: 20,
      plan: "free"
    }
  end

  def update(actor, id, attrs, revoke_only \\ false) do
    with {:ok, uuid} <- Ecto.UUID.cast(id) do
      result =
        Repo.transaction(fn ->
          # Serialize admin role changes so concurrent demotions cannot remove all admins.
          admins =
            Repo.all(from u in User, where: u.role == "admin", order_by: u.id, lock: "FOR UPDATE")

          current = Enum.find(admins, &(&1.id == actor.id and &1.status == "active"))
          if is_nil(current), do: Repo.rollback(:forbidden)
          target = Repo.one(from u in User, where: u.id == ^uuid, lock: "FOR UPDATE")
          if is_nil(target), do: Repo.rollback(:not_found)
          reason = if is_binary(attrs["reason"]), do: String.trim(attrs["reason"]), else: ""

          if String.length(reason) < 3 or String.length(reason) > 500,
            do: Repo.rollback({:invalid, "Alasan tindakan wajib diisi (3–500 karakter)."})

          changeset = User.admin_changeset(target, if(revoke_only, do: %{}, else: attrs))
          next_role = Ecto.Changeset.get_field(changeset, :role)
          next_status = Ecto.Changeset.get_field(changeset, :status)

          if target.id == current.id and
               (revoke_only or next_role != "admin" or next_status != "active"),
             do:
               Repo.rollback(
                 {:invalid, "Gunakan admin lain untuk mengubah akses akun Anda sendiri."}
               )

          if target.role == "admin" and target.status == "active" and
               (next_role != "admin" or next_status != "active") and
               Enum.count(admins, &(&1.status == "active")) <= 1,
             do: Repo.rollback({:invalid, "Minimal satu admin aktif harus tetap tersedia."})

          invalidate = revoke_only or next_role != target.role or next_status != target.status

          changeset =
            if invalidate,
              do: Ecto.Changeset.put_change(changeset, :auth_version, target.auth_version + 1),
              else: changeset

          updated =
            case Repo.update(changeset) do
              {:ok, user} -> user
              {:error, error} -> Repo.rollback(error)
            end

          if invalidate do
            now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

            Repo.update_all(
              from(s in Session, where: s.user_id == ^target.id and is_nil(s.revoked_at)),
              set: [revoked_at: now]
            )
          end

          action = if revoke_only, do: "admin.sessions_revoke", else: "admin.user_update"

          metadata = %{
            reason: reason,
            before: Map.take(target, [:role, :status, :display_name]),
            after: Map.take(updated, [:role, :status, :display_name])
          }

          case Audit.log(action,
                 actor_id: current.id,
                 resource_type: "user",
                 resource_id: target.id,
                 metadata: metadata
               ) do
            {:ok, _} -> :ok
            {:error, error} -> Repo.rollback(error)
          end

          %{user: updated, invalidate: invalidate}
        end)

      case result do
        {:ok, %{user: user, invalidate: invalidate}} ->
          if invalidate,
            do: NobarSyncWeb.Endpoint.broadcast("socket:#{user.id}", "disconnect", %{})

          {:ok, user}

        other ->
          other
      end
    else
      _ -> {:error, :not_found}
    end
  end

  def audit do
    Repo.all(
      from l in NobarSync.Audit.Log,
        where: like(l.action, "admin.%"),
        order_by: [desc: l.inserted_at, desc: l.id],
        limit: 50,
        preload: [:actor_user]
    )
    |> Enum.map(fn log ->
      %{
        id: log.id,
        action: log.action,
        actor: log.actor_user && log.actor_user.display_name,
        resource_id: log.resource_id,
        metadata: log.metadata,
        inserted_at: log.inserted_at
      }
    end)
  end

  defp integer(value, default, max) when is_binary(value) or is_integer(value) or is_nil(value) do
    case Integer.parse(to_string(value || "")) do
      {n, ""} when n > 0 -> min(n, max)
      _ -> default
    end
  end

  defp integer(_, default, _), do: default

  defp escape(text),
    do:
      text
      |> String.replace("\\", "\\\\")
      |> String.replace("%", "\\%")
      |> String.replace("_", "\\_")
end
