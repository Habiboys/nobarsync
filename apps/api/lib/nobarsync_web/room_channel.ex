defmodule NobarSyncWeb.RoomChannel do
  use NobarSyncWeb, :channel

  alias NobarSync.Playback.RoomCoordinator
  alias NobarSync.WatchRooms
  alias NobarSyncWeb.Presence

  intercept ["presence_diff", "room.member_left"]

  def join("room:" <> room_id, payload, socket) do
    actor = actor(socket)

    with {:ok, uuid} <- Ecto.UUID.cast(room_id),
         room when not is_nil(room) <- safe_room(uuid),
         member when not is_nil(member) <- WatchRooms.active_member(room.id, actor),
         {:ok, _} <- RoomCoordinator.ensure_started(room.id) do
      socket =
        socket
        |> assign(:room_id, room.id)
        |> assign(:member_id, member.id)
        |> assign(:role, role_atom(member.role))
        |> assign(:display_name, member.display_name)
        |> assign(:tab_id, payload["tab_id"] || Ecto.UUID.generate())

      send(self(), :after_join)

      {:ok,
       Map.merge(RoomCoordinator.snapshot(room.id), %{
         member: %{id: member.id, role: member.role},
         ready:
           Enum.map(WatchRooms.list_ready(room.id), &%{member_id: &1.member_id, ready: &1.ready})
       }), socket}
    else
      _ -> {:error, %{code: "forbidden", message: "Tidak bisa masuk room"}}
    end
  end

  def handle_info(:after_join, socket) do
    {:ok, _} =
      Presence.track(socket, socket.assigns.member_id, %{
        tab_id: socket.assigns.tab_id,
        role: Atom.to_string(socket.assigns.role),
        display_name: socket.assigns.display_name,
        online_at: System.os_time(:second)
      })

    push(socket, "room.presence", %{v: 1, presence: Presence.list(socket)})
    sync_presence(socket)
    {:noreply, socket}
  end

  def handle_out("presence_diff", _payload, socket) do
    push(socket, "room.presence", %{v: 1, presence: Presence.list(socket)})
    sync_presence(socket)
    {:noreply, socket}
  end

  def handle_out("room.member_left", %{member_id: id}, socket) do
    if id == socket.assigns.member_id do
      push(socket, "room.error", %{code: "left", member_id: id})
      {:stop, :normal, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_in("clock.ping", payload, socket) do
    {:reply, {:ok, %{v: 1, t0: payload["t0"], server_wall_ms: System.os_time(:millisecond)}},
     socket}
  end

  def handle_in("playback." <> kind, payload, socket) when kind in ["play", "pause", "seek"] do
    command(socket, String.to_existing_atom(kind), payload)
  end

  def handle_in("playback.countdown", payload, socket) do
    command(socket, :countdown, payload)
  end

  def handle_in("playback.sync", payload, socket) do
    kind = if payload["status"] == "playing", do: :play, else: :pause
    command(socket, kind, payload)
  end

  def handle_in("player.ready", payload, socket), do: signal(socket, payload, false)
  def handle_in("player.buffering", payload, socket), do: signal(socket, payload, true)

  def handle_in("playback.heartbeat", payload, socket) do
    RoomCoordinator.heartbeat(socket.assigns.room_id, %{
      member_id: socket.assigns.member_id,
      display_name: socket.assigns.display_name,
      position_ms: payload["position_ms"],
      paused: payload["paused"] == true,
      drift_ms: payload["drift_ms"],
      buffering: payload["buffering"] == true,
      duration_ms: payload["duration_ms"],
      role: socket.assigns.role
    })

    {:noreply, socket}
  end

  def handle_in("chat.send", payload, socket) do
    with {:ok, room, member} <- active_chat_actor(socket),
         {:ok, message} <-
           NobarSync.Messaging.send_message(room, member, payload["body"], %{
             reply_to_id: payload["reply_to_id"]
           }) do
      serialized = NobarSync.Messaging.serialize_message(message)
      broadcast!(socket, "chat.message", serialized)
      {:reply, {:ok, serialized}, socket}
    else
      {:error, reason} -> {:reply, {:error, %{code: to_string(reason)}}, socket}
    end
  end

  def handle_in("chat.edit", payload, socket) do
    with {:ok, room, member} <- active_chat_actor(socket),
         {:ok, message} <-
           NobarSync.Messaging.edit_message(room, member, payload["id"], payload["body"]) do
      serialized = NobarSync.Messaging.serialize_message(message)
      broadcast!(socket, "chat.edited", serialized)
      {:reply, {:ok, serialized}, socket}
    else
      {:error, reason} -> {:reply, {:error, %{code: to_string(reason)}}, socket}
    end
  end

  def handle_in("chat.delete", payload, socket) do
    with {:ok, room, member} <- active_chat_actor(socket),
         {:ok, message} <- NobarSync.Messaging.delete_message(room, member, payload["id"]) do
      broadcast!(socket, "chat.deleted", %{v: 1, id: message.id})
      {:reply, :ok, socket}
    else
      {:error, reason} -> {:reply, {:error, %{code: to_string(reason)}}, socket}
    end
  end

  def handle_in("chat.react", payload, socket) do
    with {:ok, room, member} <- active_chat_actor(socket),
         {:ok, result} <-
           NobarSync.Messaging.toggle_message_reaction(
             room,
             member,
             payload["id"],
             payload["emoji"]
           ) do
      broadcast!(socket, "chat.reacted", %{
        v: 1,
        id: result.message_id,
        reactions: result.reactions
      })

      {:reply, :ok, socket}
    else
      {:error, reason} -> {:reply, {:error, %{code: to_string(reason)}}, socket}
    end
  end

  def handle_in("chat.pin", payload, socket) do
    with {:ok, room, member} <- active_chat_actor(socket),
         {:ok, pinned} <-
           NobarSync.Messaging.pin_message(
             room,
             member,
             payload["id"],
             payload["pinned"] != false
           ) do
      broadcast!(socket, "chat.pinned", %{
        v: 1,
        message: pinned && NobarSync.Messaging.serialize_message(pinned)
      })

      {:reply, :ok, socket}
    else
      {:error, reason} -> {:reply, {:error, %{code: to_string(reason)}}, socket}
    end
  end

  def handle_in("chat.typing", payload, socket) do
    now = System.monotonic_time(:millisecond)
    last = socket.assigns[:last_typing] || now - 800
    typing = payload["typing"] == true

    if typing and now - last < 800 do
      {:noreply, socket}
    else
      case active_chat_actor(socket) do
        {:ok, room, member} ->
          if NobarSync.Messaging.can_chat?(room, member) do
            broadcast_from!(socket, "chat.typing", %{
              v: 1,
              member_id: member.id,
              display_name: member.display_name,
              typing: typing
            })
          end

          {:noreply, assign(socket, :last_typing, now)}

        _ ->
          {:noreply, socket}
      end
    end
  end

  def handle_in("reaction.send", %{"emoji" => emoji}, socket) do
    now = System.monotonic_time(:millisecond)
    last = socket.assigns[:last_reaction] || now - 140

    if now - last < 140 do
      {:reply, {:error, %{code: "rate_limited"}}, socket}
    else
      with {:ok, room, member} <- active_chat_actor(socket),
           {:ok, reaction} <- NobarSync.Messaging.send_reaction(room, member, emoji) do
        broadcast!(socket, "reaction.broadcast", %{
          v: 1,
          emoji: reaction.emoji,
          display_name: reaction.display_name
        })

        {:reply, :ok, assign(socket, :last_reaction, now)}
      else
        {:error, reason} -> {:reply, {:error, %{code: to_string(reason)}}, socket}
      end
    end
  end

  def handle_in(_event, _payload, socket) do
    {:reply, {:error, %{code: "invalid"}}, socket}
  end

  defp command(socket, type, payload) do
    member = WatchRooms.active_member(socket.assigns.room_id, actor(socket))
    role = if member, do: role_atom(member.role), else: :removed

    result =
      RoomCoordinator.command(socket.assigns.room_id, %{
        type: type,
        role: role,
        request_id: payload["request_id"] || Ecto.UUID.generate(),
        member_id: socket.assigns.member_id,
        position_ms: payload["position_ms"],
        rtt_ms: payload["rtt_ms"] || 0
      })

    case result do
      {:ok, snapshot} -> {:reply, {:ok, snapshot}, socket}
      {:error, reason} -> {:reply, {:error, %{code: to_string(reason)}}, socket}
    end
  end

  defp signal(socket, payload, buffering) do
    RoomCoordinator.player_signal(socket.assigns.room_id, %{
      member_id: socket.assigns.member_id,
      role: socket.assigns.role,
      online: true,
      buffering: buffering,
      position_ms: payload["position_ms"],
      ready: payload["ready"] != false and not buffering
    })

    {:reply, {:ok, %{ok: true}}, socket}
  end

  defp sync_presence(socket) do
    members =
      Presence.list(socket)
      |> Enum.map(fn {member_id, %{metas: metas}} ->
        meta = List.first(metas) || %{}

        %{
          member_id: member_id,
          display_name: meta[:display_name] || meta["display_name"] || "Penonton",
          online: metas != [],
          role: role_atom(meta[:role] || meta["role"] || "viewer")
        }
      end)

    RoomCoordinator.presence(socket.assigns.room_id, members)
    WatchRooms.mark_occupancy(socket.assigns.room_id, length(members))

    NobarSync.Playback.Broadcaster.broadcast("monitor:changes", "room.changed", %{
      room_id: socket.assigns.room_id
    })
  end

  defp actor(socket) do
    user = if socket.assigns.user_id, do: NobarSync.Accounts.get_user(socket.assigns.user_id)

    guest =
      if socket.assigns.guest_id,
        do: NobarSync.Repo.get(NobarSync.Accounts.GuestIdentity, socket.assigns.guest_id)

    %{user: user, guest: guest}
  end

  def terminate(_reason, %{assigns: %{member_id: id}} = socket) do
    Presence.untrack(socket, id)
    sync_presence(socket)
    :ok
  end

  def terminate(_, _), do: :ok

  defp active_chat_actor(socket) do
    case safe_room(socket.assigns.room_id) do
      nil ->
        {:error, :not_found}

      room ->
        case WatchRooms.active_member(room.id, actor(socket)) do
          nil -> {:error, :forbidden}
          member -> {:ok, room, member}
        end
    end
  end

  defp safe_room(id) do
    try do
      WatchRooms.get_room!(id)
    rescue
      Ecto.NoResultsError -> nil
    end
  end

  defp role_atom("host"), do: :host
  defp role_atom("moderator"), do: :moderator
  defp role_atom(:host), do: :host
  defp role_atom(:moderator), do: :moderator
  defp role_atom(_), do: :viewer
end
