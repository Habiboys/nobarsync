defmodule NobarSyncWeb.RoomChannel do
  use NobarSyncWeb, :channel

  alias NobarSync.Playback.RoomCoordinator
  alias NobarSync.WatchRooms
  alias NobarSyncWeb.Presence

  intercept ["presence_diff"]

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
    room = WatchRooms.get_room!(socket.assigns.room_id)
    member = NobarSync.Repo.get!(NobarSync.WatchRooms.Member, socket.assigns.member_id)

    case NobarSync.Messaging.send_message(room, member, payload["body"]) do
      {:ok, message} ->
        broadcast!(socket, "chat.message", %{
          v: 1,
          id: message.id,
          body: message.body,
          display_name: message.display_name,
          member_id: message.member_id,
          inserted_at: message.inserted_at
        })

        {:reply, :ok, socket}

      {:error, reason} ->
        {:reply, {:error, %{code: to_string(reason)}}, socket}
    end
  end

  def handle_in("reaction.send", %{"emoji" => emoji}, socket) do
    now = System.monotonic_time(:millisecond)
    last = socket.assigns[:last_reaction] || now - 140

    if now - last < 140 do
      {:reply, {:error, %{code: "rate_limited"}}, socket}
    else
      room = WatchRooms.get_room!(socket.assigns.room_id)
      member = NobarSync.Repo.get!(NobarSync.WatchRooms.Member, socket.assigns.member_id)

      case NobarSync.Messaging.send_reaction(room, member, emoji) do
        {:ok, reaction} ->
          broadcast!(socket, "reaction.broadcast", %{
            v: 1,
            emoji: reaction.emoji,
            display_name: reaction.display_name
          })

          {:reply, :ok, assign(socket, :last_reaction, now)}

        {:error, reason} ->
          {:reply, {:error, %{code: to_string(reason)}}, socket}
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
  end

  defp actor(socket) do
    user = if socket.assigns.user_id, do: NobarSync.Accounts.get_user(socket.assigns.user_id)

    guest =
      if socket.assigns.guest_id,
        do: NobarSync.Repo.get(NobarSync.Accounts.GuestIdentity, socket.assigns.guest_id)

    %{user: user, guest: guest}
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
