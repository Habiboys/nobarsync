defmodule NobarSyncWeb.LiveBoard do
  @moduledoc false

  import Ecto.Query
  alias NobarSync.Media.Asset
  alias NobarSync.Playback.{Snapshot, Timeline}
  alias NobarSync.Repo
  alias NobarSync.WatchRooms
  alias NobarSync.WatchRooms.Member
  alias NobarSyncWeb.Presence

  def people(room_id, opts \\ []) do
    present = Presence.list("room:#{room_id}")

    members =
      case Map.keys(present) do
        [] ->
          %{}

        ids ->
          Member
          |> where([member], member.id in ^ids and is_nil(member.left_at) and not member.banned)
          |> preload(:user)
          |> Repo.all()
          |> Map.new(&{to_string(&1.id), &1})
      end

    present
    |> Enum.filter(fn {id, %{metas: metas}} ->
      member = Map.get(members, to_string(id))
      member && member.user && member.user.status == "active" && metas != []
    end)
    |> Enum.map(fn {id, %{metas: metas}} ->
      meta = List.first(metas) || %{}
      member = Map.get(members, to_string(id))

      row = %{
        id: to_string(id),
        display_name: name_of(member, meta),
        role: (member && member.role) || meta_value(meta, :role) || "viewer",
        user_id: member && member.user_id
      }

      if opts[:emails],
        do: Map.put(row, :email, member && member.user && member.user.email),
        else: row
    end)
    |> Enum.sort_by(&String.downcase(&1.display_name))
  end

  def admin do
    rows =
      Enum.map(WatchRooms.list_open_rooms(), fn room ->
        {room, people(room.id, emails: true), playback(room)}
      end)

    titles =
      rows
      |> Enum.map(fn {room, _people, play} -> play.media_id || room.media_asset_id end)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> titles()

    rooms =
      Enum.map(rows, fn {room, occupants, play} ->
        media_id = play.media_id || room.media_asset_id

        %{
          id: room.id,
          code: room.code,
          title: room.title,
          locked: room.locked,
          online: occupants != [],
          people: occupants,
          media_title: titles[media_id],
          playback: Map.delete(play, :media_id)
        }
      end)
      |> Enum.sort_by(fn room -> {not room.online, room.code} end)

    online =
      Enum.flat_map(rooms, fn room ->
        Enum.map(room.people, fn person ->
          Map.merge(person, %{room_code: room.code, room_title: room.title})
        end)
      end)

    %{
      people: online,
      users: online_users(),
      rooms: rooms,
      rooms_total:
        Repo.aggregate(
          from(room in NobarSync.WatchRooms.Room, where: room.status == "open"),
          :count
        ),
      sampled_at_ms: System.os_time(:millisecond)
    }
  end

  defp online_users do
    present = Presence.list("activity:online")
    ids = Map.keys(present)

    Repo.all(
      from user in NobarSync.Accounts.User, where: user.id in ^ids and user.status == "active"
    )
    |> Enum.map(fn user ->
      metas = present[to_string(user.id)].metas

      %{
        id: user.id,
        display_name: user.display_name,
        email: user.email,
        role: user.role,
        tabs: length(metas),
        pages: metas |> Enum.map(&(meta_value(&1, :page) || "/")) |> Enum.uniq(),
        online_at: metas |> Enum.map(&(meta_value(&1, :online_at) || 0)) |> Enum.min(fn -> 0 end)
      }
    end)
    |> Enum.sort_by(&String.downcase(&1.display_name))
  end

  defp titles([]), do: %{}

  defp titles(ids) do
    Repo.all(from asset in Asset, where: asset.id in ^ids, select: {asset.id, asset.title})
    |> Map.new()
  end

  defp playback(room) do
    case Registry.lookup(NobarSync.Playback.Registry, room.id) do
      [{pid, _}] ->
        try do
          from_public(GenServer.call(pid, :snapshot, 1_000), room)
        catch
          :exit, _ -> from_snapshot(room)
        end

      [] ->
        from_snapshot(room)
    end
  end

  defp from_public(snap, room) do
    state = snap.state

    view = %{
      status: state.status,
      duration_ms: snap.duration_ms || 0,
      anchor_position_ms: state.anchor_position_ms || 0,
      anchor_wall_ms: state.anchor_server_time_ms || 0,
      playback_rate: state.playback_rate || 1.0
    }

    %{
      status: Atom.to_string(state.status),
      position_ms: placed(view, snap.server_wall_ms),
      duration_ms: snap.duration_ms || 0,
      media_id: snap.media_id || room.media_asset_id
    }
  end

  defp from_snapshot(room) do
    case Repo.get(Snapshot, room.id) do
      nil ->
        %{status: "idle", position_ms: 0, duration_ms: 0, media_id: room.media_asset_id}

      snap ->
        status = status_atom(snap.status)

        view = %{
          status: status,
          duration_ms: snap.duration_ms || 0,
          anchor_position_ms: snap.anchor_position_ms || 0,
          anchor_wall_ms: snap.anchor_wall_ms || 0,
          playback_rate: snap.playback_rate || 1.0
        }

        %{
          status: Atom.to_string(status),
          position_ms: placed(view, System.os_time(:millisecond)),
          duration_ms: snap.duration_ms || 0,
          media_id: snap.media_asset_id || room.media_asset_id
        }
    end
  end

  defp placed(state, now_wall) do
    state =
      if state.status == :playing and state.anchor_wall_ms <= 0,
        do: %{state | status: :paused},
        else: state

    Timeline.position_from_wall(state, now_wall)
  end

  defp status_atom("playing"), do: :playing
  defp status_atom("paused"), do: :paused
  defp status_atom("ended"), do: :ended
  defp status_atom(_), do: :idle

  defp name_of(%{display_name: name}, _meta) when is_binary(name) and name != "", do: name
  defp name_of(_member, meta), do: meta_value(meta, :display_name) || "Penonton"

  defp meta_value(meta, key), do: Map.get(meta, key) || Map.get(meta, Atom.to_string(key))
end
