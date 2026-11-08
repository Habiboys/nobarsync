defmodule NobarSync.WatchRooms do
  @moduledoc false

  import Ecto.Query
  alias NobarSync.Repo
  alias NobarSync.WatchRooms.{Invitation, Member, PlaylistItem, PlaylistVote, ReadyCheck, Room}

  @alphabet ~c"ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

  def get_room!(id), do: Repo.get!(Room, id)

  def get_room_by_code(code) when is_binary(code),
    do: Repo.get_by(Room, code: String.upcase(code))

  def get_room_by_code(_), do: nil

  def create_room(user, attrs) do
    code = unique_code()
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    result =
      %Room{}
      |> Room.changeset(attrs)
      |> Ecto.Changeset.put_change(:code, code)
      |> Ecto.Changeset.put_change(:host_user_id, user.id)
      |> Ecto.Changeset.put_change(:status, "open")
      |> Ecto.Changeset.put_change(:empty_since, now)
      |> Repo.insert()

    with {:ok, room} <- result do
      {:ok, member} = upsert_member(room, %{user: user, guest: nil}, "host", user.display_name)
      if media_id = attrs["media_id"], do: set_media(room, user, media_id)
      {:ok, %{room: Repo.get!(Room, room.id), member: member}}
    end
  end

  def update_room(room, attrs) do
    room |> Room.changeset(attrs) |> Repo.update()
  end

  def close_room(room) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
    room |> Ecto.Changeset.change(status: "closed", empty_since: now) |> Repo.update()
  end

  def delete_room(room) do
    Repo.delete(room)
  end

  def join(_room, %{user: nil}, _password), do: {:error, :unauthorized}

  def join(room, actor, password) do
    Repo.transaction(fn ->
      locked = Repo.one!(from r in Room, where: r.id == ^room.id, lock: "FOR UPDATE")

      case join_member(locked, actor, password) do
        {:ok, member} -> member
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp join_member(room, actor, password) do
    actor = Map.put(actor, :guest, nil)
    existing = find_member(room.id, actor)
    active_count = count_active(room.id)

    cond do
      room.status != "open" ->
        {:error, :not_found}

      expired?(room) ->
        {:error, :expired}

      existing && existing.banned ->
        {:error, :forbidden}

      room.locked && (is_nil(existing) || existing.left_at) ->
        {:error, :room_locked}

      room.visibility == "password" && !password_ok?(room, password) &&
          (is_nil(existing) || existing.left_at) ->
        {:error, :forbidden}

      active_count >= room.max_viewers && (is_nil(existing) || existing.left_at) ->
        {:error, :room_full}

      true ->
        owner? = room.host_user_id && actor.user && actor.user.id == room.host_user_id

        role =
          cond do
            owner? -> "host"
            existing && is_nil(existing.left_at) && existing.role != "host" -> existing.role
            true -> "viewer"
          end

        name = display_name(actor)

        with {:ok, member} <- upsert_member(room, actor, role, name) do
          if member.role == "host", do: demote_other_hosts(room.id, member.id)
          {:ok, member}
        end
    end
  end

  def leave(room, actor) do
    case find_member(room.id, actor) do
      nil ->
        {:error, :not_found}

      member ->
        now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
        {:ok, member} = member |> Ecto.Changeset.change(left_at: now) |> Repo.update()

        if member.role == "host" and room.host_transfer_policy == "transfer" do
          transfer_host_auto(room.id)
        end

        mark_empty_if_needed(room.id)
        {:ok, member}
    end
  end

  def kick(room, actor_member, target_id) do
    if actor_member.role in ["host", "moderator"] do
      case Repo.get_by(Member, id: target_id, room_id: room.id) do
        nil ->
          {:error, :not_found}

        %{role: "host"} ->
          {:error, :forbidden}

        member ->
          now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
          member |> Ecto.Changeset.change(left_at: now, banned: true) |> Repo.update()
      end
    else
      {:error, :forbidden}
    end
  end

  def transfer_host(room, actor_member, target_id) do
    if actor_member.role == "host" do
      case Repo.one(
             from m in Member,
               where:
                 m.id == ^target_id and m.room_id == ^room.id and is_nil(m.left_at) and
                   m.banned == false
           ) do
        nil ->
          {:error, :not_found}

        target ->
          Repo.transaction(fn ->
            Repo.update_all(from(m in Member, where: m.room_id == ^room.id and m.role == "host"),
              set: [role: "viewer"]
            )

            {:ok, target} = target |> Ecto.Changeset.change(role: "host") |> Repo.update()
            host_user_id = target.user_id

            {:ok, room} =
              room |> Ecto.Changeset.change(host_user_id: host_user_id) |> Repo.update()

            {room, target}
          end)
      end
    else
      {:error, :forbidden}
    end
  end

  def transfer_host_auto(room_id) do
    room = get_room!(room_id)

    if room.host_transfer_policy != "transfer" do
      {:error, :skipped}
    else
      next =
        Member
        |> where(
          [m],
          m.room_id == ^room_id and is_nil(m.left_at) and m.banned == false and m.role != "host"
        )
        |> order_by([m],
          asc: fragment("CASE WHEN ? = 'moderator' THEN 0 ELSE 1 END", m.role),
          asc: m.joined_at
        )
        |> limit(1)
        |> Repo.one()

      active_host? =
        Repo.exists?(
          from m in Member,
            where:
              m.room_id == ^room_id and m.role == "host" and is_nil(m.left_at) and
                m.banned == false
        )

      cond do
        active_host? ->
          {:error, :host_present}

        next ->
          {:ok, {room, member}} =
            Repo.transaction(fn ->
              Repo.update_all(
                from(m in Member, where: m.room_id == ^room_id and m.role == "host"),
                set: [role: "viewer"]
              )

              Repo.update_all(from(m in Member, where: m.id == ^next.id), set: [role: "host"])

              {:ok, room} =
                room |> Ecto.Changeset.change(host_user_id: next.user_id) |> Repo.update()

              {room, Repo.get!(Member, next.id)}
            end)

          {:ok, room, member}

        true ->
          {:error, :nobody}
      end
    end
  end

  def set_lock(room, locked) when is_boolean(locked) do
    room |> Ecto.Changeset.change(locked: locked) |> Repo.update()
  end

  # A room has one active title and any number of queued titles. Selecting one
  # consumes that title only; the remainder of the playlist is preserved.
  def set_media(room, user, media_id) do
    Repo.transaction(fn ->
      locked = lock_playlist_room(room.id)
      asset = playlist_asset!(locked, user, media_id)

      case locked |> Ecto.Changeset.change(media_asset_id: asset.id) |> Repo.update() do
        {:ok, updated} ->
          Repo.delete_all(
            from p in PlaylistItem,
              where: p.room_id == ^locked.id and p.media_asset_id == ^asset.id
          )

          updated

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
  end

  def active_member(room_id, %{user: %{id: id}}) when is_binary(id) do
    Repo.one(
      from m in Member,
        where:
          m.room_id == ^room_id and m.user_id == ^id and is_nil(m.left_at) and m.banned == false
    )
  end

  def active_member(_, _), do: nil

  def list_members(room_id) do
    Member
    |> where([m], m.room_id == ^room_id and is_nil(m.left_at) and m.banned == false)
    |> order_by([m], asc: m.joined_at)
    |> Repo.all()
  end

  def dashboard(user) do
    memberships =
      Member
      |> join(:inner, [m], r in Room, on: r.id == m.room_id)
      |> where([m], m.user_id == ^user.id)
      |> order_by([m], desc: m.updated_at)
      |> select([m, r], {m, r})
      |> Repo.all()

    active =
      memberships
      |> Enum.filter(fn {member, room} -> is_nil(member.left_at) and room.status == "open" end)
      |> Enum.map(fn {_member, room} -> room end)
      |> Enum.uniq_by(& &1.id)

    active_ids = MapSet.new(active, & &1.id)

    history =
      memberships
      |> Enum.map(fn {_member, room} -> room end)
      |> Enum.uniq_by(& &1.id)
      |> Enum.reject(&MapSet.member?(active_ids, &1.id))
      |> Enum.take(20)

    %{active: active, history: history}
  end

  def create_invitation(room, user) do
    %Invitation{}
    |> Ecto.Changeset.change(%{
      room_id: room.id,
      code: unique_code(),
      created_by_id: user.id,
      expires_at:
        DateTime.add(
          DateTime.utc_now() |> DateTime.truncate(:microsecond),
          7 * 24 * 3600,
          :second
        ),
      max_uses: 50,
      use_count: 0
    })
    |> Repo.insert()
  end

  def add_playlist(room, user, media_id) do
    Repo.transaction(fn ->
      locked = lock_playlist_room(room.id)
      asset = playlist_asset!(locked, user, media_id)

      if locked.media_asset_id == asset.id,
        do: Repo.rollback({:invalid, "Film ini sedang aktif. Pilih film lain untuk antrean."})

      # Serialize sequence allocation per room. Repeated requests for one title
      # return the existing item rather than creating duplicates or colliding.
      existing =
        Repo.one(
          from p in PlaylistItem,
            where: p.room_id == ^locked.id and p.media_asset_id == ^asset.id,
            limit: 1
        )

      if existing do
        existing
      else
        position =
          (Repo.aggregate(
             from(p in PlaylistItem, where: p.room_id == ^locked.id),
             :max,
             :position
           ) || 0) + 1

        attrs = %{
          room_id: locked.id,
          media_asset_id: asset.id,
          position: position,
          added_by_id: user.id
        }

        case %PlaylistItem{} |> PlaylistItem.changeset(attrs) |> Repo.insert() do
          {:ok, item} -> item
          {:error, reason} -> Repo.rollback(reason)
        end
      end
    end)
  end

  def remove_playlist(room, item_id) do
    with {:ok, id} <- Ecto.UUID.cast(item_id) do
      case Repo.get_by(PlaylistItem, id: id, room_id: room.id) do
        nil -> {:error, :not_found}
        item -> Repo.delete(item)
      end
    else
      _ -> {:error, :invalid}
    end
  end

  defp lock_playlist_room(room_id) do
    case Repo.one(from r in Room, where: r.id == ^room_id, lock: "FOR UPDATE") do
      nil -> Repo.rollback(:not_found)
      %{status: "open"} = room -> room
      _ -> Repo.rollback({:invalid, "Ruang sudah ditutup."})
    end
  end

  defp playlist_asset!(room, user, media_id) do
    with {:ok, id} <- Ecto.UUID.cast(media_id),
         %{} = asset <- NobarSync.Media.get_asset(id) do
      shared_in_room =
        room.media_asset_id == id or
          Repo.exists?(
            from p in PlaylistItem,
              where: p.room_id == ^room.id and p.media_asset_id == ^id
          )

      cond do
        is_nil(user) ->
          Repo.rollback(:unauthorized)

        not (asset.owner_id == user.id or user.role == "admin" or asset.visibility == "library" or
                 shared_in_room) ->
          Repo.rollback(:forbidden)

        asset.status != "ready" ->
          Repo.rollback(:media_not_ready)

        true ->
          asset
      end
    else
      _ -> Repo.rollback(:not_found)
    end
  end

  def list_playlist(room_id) do
    PlaylistItem
    |> where([p], p.room_id == ^room_id)
    |> order_by([p], asc: p.position)
    |> preload(:media_asset)
    |> Repo.all()
    |> Enum.map(fn item ->
      votes =
        Repo.aggregate(from(v in PlaylistVote, where: v.playlist_item_id == ^item.id), :count)

      %{item: item, votes: votes}
    end)
  end

  def vote(item_id, member) do
    %PlaylistVote{}
    |> Ecto.Changeset.change(%{playlist_item_id: item_id, room_member_id: member.id})
    |> Repo.insert(on_conflict: :nothing, conflict_target: [:playlist_item_id, :room_member_id])
  end

  def next_media(room) do
    list_playlist(room.id)
    |> Enum.sort_by(fn row -> {-row.votes, row.item.position} end)
    |> List.first()
  end

  def set_ready(room, member, ready) do
    Repo.insert(
      %ReadyCheck{room_id: room.id, member_id: member.id, ready: ready},
      on_conflict: [
        set: [ready: ready, updated_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)]
      ],
      conflict_target: [:room_id, :member_id]
    )
  end

  def list_ready(room_id), do: Repo.all(from r in ReadyCheck, where: r.room_id == ^room_id)

  def mark_occupancy(room_id, online_count) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    if online_count > 0 do
      Repo.update_all(from(r in Room, where: r.id == ^room_id), set: [empty_since: nil])
    else
      Repo.update_all(from(r in Room, where: r.id == ^room_id and is_nil(r.empty_since)),
        set: [empty_since: now]
      )
    end
  end

  def close_expired_empty do
    now = DateTime.utc_now()

    Room
    |> where([r], r.status == "open" and not is_nil(r.empty_since))
    |> Repo.all()
    |> Enum.each(fn room ->
      if DateTime.diff(now, room.empty_since, :second) >= room.empty_ttl_seconds do
        room |> Ecto.Changeset.change(status: "closed") |> Repo.update()
      end
    end)
  end

  def list_open_rooms do
    Repo.all(
      from r in Room, where: r.status == "open", order_by: [desc: r.inserted_at], limit: 100
    )
  end

  defp demote_other_hosts(room_id, host_member_id) do
    Repo.update_all(
      from(m in Member,
        where: m.room_id == ^room_id and m.role == "host" and m.id != ^host_member_id
      ),
      set: [role: "viewer"]
    )
  end

  defp upsert_member(room, actor, role, name) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
    existing = find_member(room.id, actor)

    member =
      if existing do
        existing
        |> Ecto.Changeset.change(%{
          role: role,
          display_name: name,
          left_at: nil,
          joined_at: now,
          banned: false
        })
        |> Repo.update!()
      else
        %Member{}
        |> Ecto.Changeset.change(%{
          room_id: room.id,
          user_id: actor.user && actor.user.id,
          guest_identity_id: actor.guest && actor.guest.id,
          role: role,
          display_name: name,
          joined_at: now,
          banned: false
        })
        |> Repo.insert!()
      end

    mark_occupancy(room.id, count_active(room.id))
    {:ok, member}
  end

  defp find_member(room_id, %{user: %{id: id}}) when is_binary(id) do
    Repo.one(
      from m in Member,
        where: m.room_id == ^room_id and m.user_id == ^id,
        order_by: [desc: m.inserted_at],
        limit: 1
    )
  end

  defp find_member(room_id, %{guest: %{id: id}}) when is_binary(id) do
    Repo.one(
      from m in Member,
        where: m.room_id == ^room_id and m.guest_identity_id == ^id,
        order_by: [desc: m.inserted_at],
        limit: 1
    )
  end

  defp find_member(_, _), do: nil

  defp count_active(room_id) do
    Repo.aggregate(
      from(m in Member, where: m.room_id == ^room_id and is_nil(m.left_at) and m.banned == false),
      :count
    )
  end

  defp password_ok?(%{password_hash: hash}, password)
       when is_binary(hash) and is_binary(password) do
    Bcrypt.verify_pass(password, hash)
  end

  defp password_ok?(_, _), do: false

  defp expired?(%{expires_at: nil}), do: false
  defp expired?(%{expires_at: at}), do: DateTime.compare(at, DateTime.utc_now()) == :lt

  defp display_name(%{user: %{display_name: name}}) when is_binary(name), do: name
  defp display_name(%{guest: %{display_name: name}}) when is_binary(name), do: name
  defp display_name(_), do: "Tamu"

  defp unique_code do
    code = for(_ <- 1..6, into: "", do: <<Enum.random(@alphabet)>>)

    if Repo.get_by(Room, code: code) || Repo.get_by(Invitation, code: code),
      do: unique_code(),
      else: code
  end

  defp mark_empty_if_needed(room_id) do
    if count_active(room_id) == 0, do: mark_occupancy(room_id, 0)
  end
end
