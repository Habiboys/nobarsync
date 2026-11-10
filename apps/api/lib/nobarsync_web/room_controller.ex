defmodule NobarSyncWeb.RoomController do
  use NobarSyncWeb, :controller

  alias NobarSync.{Audit, Media, Messaging, WatchRooms}
  alias NobarSync.Playback.Broadcaster
  alias NobarSyncWeb.MediaController

  def index(conn, _params) do
    data = WatchRooms.dashboard(conn.assigns.current_user)

    json(conn, %{
      active: Enum.map(data.active, &room_json/1),
      history: Enum.map(data.history, &room_json/1)
    })
  end

  def create(conn, params) do
    with {:ok, %{room: room, member: member}} <-
           WatchRooms.create_room(conn.assigns.current_user, params) do
      Audit.log("room.create",
        actor_id: conn.assigns.current_user.id,
        resource_type: "room",
        resource_id: room.id
      )

      json(conn, %{room: room_json(room), member: member_json(member)})
    end
  end

  def show(conn, %{"code" => code}) do
    case WatchRooms.get_room_by_code(code) do
      nil ->
        {:error, :not_found}

      room ->
        json(conn, %{
          room: public_room(room),
          members: NobarSyncWeb.LiveBoard.people(room.id),
          membership: membership_json(room, conn)
        })
    end
  end

  def join(conn, %{"code" => code} = params) do
    with %{} = room <- WatchRooms.get_room_by_code(code),
         {:ok, member} <- WatchRooms.join(room, actor(conn), params["password"]) do
      json(conn, %{room: room_json(room), member: member_json(member)})
    else
      nil -> {:error, :not_found}
      other -> other
    end
  end

  def leave(conn, %{"code" => code}) do
    with %{} = room <- WatchRooms.get_room_by_code(code),
         {:ok, member} <- WatchRooms.leave(room, actor(conn)) do
      Broadcaster.broadcast("room:#{room.id}", "room.member_left", %{member_id: member.id})
      Broadcaster.broadcast("monitor:changes", "room.changed", %{room_id: room.id})
      json(conn, %{ok: true})
    else
      nil -> {:error, :not_found}
      other -> other
    end
  end

  def close(conn, %{"code" => code}) do
    with %{} = room <- WatchRooms.get_room_by_code(code),
         true <- host?(conn, room),
         {:ok, room} <- WatchRooms.close_room(room) do
      NobarSync.Playback.RoomCoordinator.stop(room.id)

      Broadcaster.broadcast("room:#{room.id}", "room.closed", %{v: 1, room_id: room.id})
      json(conn, %{room: room_json(room)})
    else
      false -> {:error, :forbidden}
      nil -> {:error, :not_found}
      other -> other
    end
  end

  def delete(conn, %{"code" => code}) do
    with %{} = room <- WatchRooms.get_room_by_code(code),
         true <- host?(conn, room) do
      NobarSync.Playback.RoomCoordinator.stop(room.id)

      case WatchRooms.delete_room(room) do
        {:ok, _} -> json(conn, %{ok: true})
        other -> other
      end
    else
      false -> {:error, :forbidden}
      nil -> {:error, :not_found}
    end
  end

  def settings(conn, %{"code" => code} = params) do
    with %{} = room <- WatchRooms.get_room_by_code(code),
         %{} = member <- WatchRooms.active_member(room.id, actor(conn)),
         true <- member.role in ["host", "moderator"],
         {:ok, room} <- WatchRooms.update_room(room, params) do
      NobarSync.Playback.RoomCoordinator.ensure_started(room.id)

      NobarSync.Playback.RoomCoordinator.settings(room.id, %{
        control_mode: String.to_existing_atom(room.control_mode),
        buffering_mode: String.to_existing_atom(room.buffering_mode)
      })

      Broadcaster.broadcast("room:#{room.id}", "room.settings_changed", %{
        v: 1,
        room: room_json(room)
      })

      json(conn, %{room: room_json(room)})
    else
      nil -> {:error, :not_found}
      false -> {:error, :forbidden}
      other -> other
    end
  end

  def lock(conn, %{"code" => code} = params) do
    with %{} = room <- WatchRooms.get_room_by_code(code),
         %{} = member <- WatchRooms.active_member(room.id, actor(conn)),
         true <- member.role == "host",
         {:ok, room} <- WatchRooms.set_lock(room, params["locked"] == true) do
      json(conn, %{room: room_json(room)})
    else
      false -> {:error, :forbidden}
      nil -> {:error, :not_found}
      other -> other
    end
  end

  def kick(conn, %{"code" => code, "member_id" => member_id}) do
    with %{} = room <- WatchRooms.get_room_by_code(code),
         %{} = member <- WatchRooms.active_member(room.id, actor(conn)),
         {:ok, _} <- WatchRooms.kick(room, member, member_id) do
      Broadcaster.broadcast("room:#{room.id}", "room.error", %{
        v: 1,
        code: "kicked",
        member_id: member_id
      })

      json(conn, %{ok: true})
    else
      nil -> {:error, :not_found}
      other -> other
    end
  end

  def transfer(conn, %{"code" => code, "member_id" => member_id}) do
    with %{} = room <- WatchRooms.get_room_by_code(code),
         %{} = member <- WatchRooms.active_member(room.id, actor(conn)),
         {:ok, {room, target}} <- WatchRooms.transfer_host(room, member, member_id) do
      Broadcaster.broadcast("room:#{room.id}", "room.host_changed", %{
        v: 1,
        room_id: room.id,
        member_id: target.id,
        display_name: target.display_name
      })

      json(conn, %{room: room_json(room), member: member_json(target)})
    else
      nil -> {:error, :not_found}
      other -> other
    end
  end

  def set_media(conn, %{"code" => code, "media_id" => media_id}) do
    with %{} = room <- WatchRooms.get_room_by_code(code),
         %{} = member <- WatchRooms.active_member(room.id, actor(conn)),
         true <- member.role in ["host", "moderator"],
         {:ok, _} <- NobarSync.Playback.RoomCoordinator.ensure_started(room.id),
         {:ok, room} <- WatchRooms.set_media(room, conn.assigns.current_user, media_id),
         %{} = asset <- Media.get_asset(media_id),
         {:ok, snapshot} <-
           NobarSync.Playback.RoomCoordinator.command(room.id, %{
             type: :change_media,
             role: String.to_existing_atom(member.role),
             request_id: Ecto.UUID.generate(),
             member_id: member.id,
             media_id: asset.id,
             duration_ms: asset.duration_ms || 0,
             media_status: asset.status,
             provider: asset.provider,
             rtt_ms: 0
           }) do
      Broadcaster.broadcast("room:#{room.id}", "room.settings_changed", %{v: 1, playlist: true})

      json(conn, %{
        room: room_json(room),
        media: MediaController.asset_json(asset),
        snapshot: snapshot
      })
    else
      false -> {:error, :forbidden}
      nil -> {:error, :not_found}
      other -> other
    end
  end

  def playback(conn, %{"code" => code}) do
    with %{} = room <- WatchRooms.get_room_by_code(code),
         %{} = _member <- WatchRooms.active_member(room.id, actor(conn)) do
      NobarSync.Playback.RoomCoordinator.ensure_started(room.id)
      json(conn, %{snapshot: NobarSync.Playback.RoomCoordinator.snapshot(room.id)})
    else
      nil -> {:error, :not_found}
    end
  end

  def playlist(conn, %{"code" => code}) do
    with %{} = room <- WatchRooms.get_room_by_code(code),
         %{} <- WatchRooms.active_member(room.id, actor(conn)) do
      rows = WatchRooms.list_playlist(room.id)

      json(conn, %{
        items:
          Enum.map(rows, fn row ->
            %{
              id: row.item.id,
              position: row.item.position,
              votes: row.votes,
              media: media_brief(row.item.media_asset)
            }
          end)
      })
    else
      nil -> {:error, :not_found}
    end
  end

  def add_playlist(conn, %{"code" => code, "media_id" => media_id}) do
    with %{} = room <- WatchRooms.get_room_by_code(code),
         %{} = member <- WatchRooms.active_member(room.id, actor(conn)),
         true <- member.role in ["host", "moderator"],
         {:ok, item} <- WatchRooms.add_playlist(room, conn.assigns.current_user, media_id) do
      Broadcaster.broadcast("room:#{room.id}", "room.settings_changed", %{v: 1, playlist: true})
      json(conn, %{id: item.id, position: item.position})
    else
      false -> {:error, :forbidden}
      nil -> {:error, :not_found}
      other -> other
    end
  end

  def remove_playlist(conn, %{"code" => code, "item_id" => item_id}) do
    with %{} = room <- WatchRooms.get_room_by_code(code),
         %{} = member <- WatchRooms.active_member(room.id, actor(conn)),
         true <- member.role in ["host", "moderator"],
         {:ok, _} <- WatchRooms.remove_playlist(room, item_id) do
      Broadcaster.broadcast("room:#{room.id}", "room.settings_changed", %{v: 1, playlist: true})
      json(conn, %{ok: true})
    else
      false -> {:error, :forbidden}
      nil -> {:error, :not_found}
      other -> other
    end
  end

  def vote(conn, %{"code" => code, "item_id" => item_id}) do
    with %{} = room <- WatchRooms.get_room_by_code(code),
         %{} = member <- WatchRooms.active_member(room.id, actor(conn)),
         true <- Enum.any?(WatchRooms.list_playlist(room.id), &(&1.item.id == item_id)),
         {:ok, _} <- WatchRooms.vote(item_id, member) do
      Broadcaster.broadcast("room:#{room.id}", "room.settings_changed", %{v: 1, playlist: true})
      json(conn, %{ok: true})
    else
      false -> {:error, :forbidden}
      nil -> {:error, :not_found}
      other -> other
    end
  end

  def ready(conn, %{"code" => code} = params) do
    with %{} = room <- WatchRooms.get_room_by_code(code),
         %{} = member <- WatchRooms.active_member(room.id, actor(conn)),
         {:ok, _} <- WatchRooms.set_ready(room, member, params["ready"] == true) do
      Broadcaster.broadcast("room:#{room.id}", "room.settings_changed", %{
        v: 1,
        ready:
          Enum.map(WatchRooms.list_ready(room.id), &%{member_id: &1.member_id, ready: &1.ready})
      })

      json(conn, %{ok: true})
    else
      nil -> {:error, :not_found}
      other -> other
    end
  end

  def messages(conn, %{"code" => code}) do
    with %{} = room <- WatchRooms.get_room_by_code(code),
         %{} <- WatchRooms.active_member(room.id, actor(conn)) do
      json(conn, %{messages: Enum.map(Messaging.list_messages(room.id), &message_json/1)})
    else
      nil -> {:error, :not_found}
    end
  end

  def invite(conn, %{"code" => code}) do
    with %{} = room <- WatchRooms.get_room_by_code(code),
         %{} = member <- WatchRooms.active_member(room.id, actor(conn)),
         true <- member.role in ["host", "moderator"],
         {:ok, invite} <- WatchRooms.create_invitation(room, conn.assigns.current_user) do
      json(conn, %{code: invite.code, expires_at: invite.expires_at})
    else
      false -> {:error, :forbidden}
      nil -> {:error, :not_found}
      other -> other
    end
  end

  defp actor(conn), do: %{user: conn.assigns.current_user, guest: conn.assigns.current_guest}

  defp host?(conn, room) do
    user = conn.assigns.current_user
    member = WatchRooms.active_member(room.id, %{user: user, guest: nil})
    (user && user.role == "admin") or (member && member.role == "host")
  end

  def room_json(room) do
    %{
      id: room.id,
      code: room.code,
      title: room.title,
      visibility: room.visibility,
      max_viewers: room.max_viewers,
      control_mode: room.control_mode,
      buffering_mode: room.buffering_mode,
      chat_permission: room.chat_permission,
      locked: room.locked,
      status: room.status,
      media_id: room.media_asset_id,
      host_user_id: room.host_user_id
    }
  end

  defp public_room(room), do: room_json(room)

  defp membership_json(room, conn) do
    case WatchRooms.active_member(room.id, actor(conn)) do
      nil -> nil
      member -> member_json(member)
    end
  end

  defp member_json(member) do
    %{
      id: member.id,
      display_name: member.display_name,
      role: member.role,
      user_id: member.user_id
    }
  end

  defp message_json(message) do
    %{
      id: message.id,
      body: message.body,
      display_name: message.display_name,
      member_id: message.member_id,
      inserted_at: message.inserted_at
    }
  end

  defp media_brief(nil), do: nil

  defp media_brief(asset),
    do: %{id: asset.id, title: asset.title, status: asset.status, duration_ms: asset.duration_ms}
end
