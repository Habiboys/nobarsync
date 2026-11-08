defmodule NobarSyncWeb.VoiceChannel do
  use Phoenix.Channel, log_handle_in: false
  alias NobarSync.{Accounts, Repo, WatchRooms}
  alias NobarSyncWeb.Presence
  intercept ["presence_diff"]

  def join("voice:" <> room_id, %{"transport" => "websocket-v2"}, socket) do
    with {:ok, uuid} <- Ecto.UUID.cast(room_id),
         %{status: "open"} <- Repo.get(WatchRooms.Room, uuid),
         %{} = member <- WatchRooms.active_member(uuid, actor(socket)) do
      socket =
        assign(socket,
          room_id: uuid,
          member_id: member.id,
          peer_id: Ecto.UUID.generate(),
          muted: true,
          last_audio_seq: -1
        )

      result =
        :global.trans({{__MODULE__, uuid}, self()}, fn ->
          if map_size(Presence.list(socket)) >= 8 do
            {:error, :full}
          else
            Presence.track(socket, socket.assigns.peer_id, %{
              display_name: member.display_name,
              member_id: member.id,
              muted: true
            })
          end
        end)

      case result do
        {:ok, _} ->
          NobarSyncWeb.Endpoint.subscribe("room:" <> uuid)
          send(self(), :participants)
          Process.send_after(self(), :authorize, 5_000)

          {:ok, %{peer_id: socket.assigns.peer_id, transport: "websocket-v2", sample_rate: 16000},
           socket}

        _ ->
          {:error, %{message: "Call penuh (maksimal 8 peserta)."}}
      end
    else
      _ -> {:error, %{message: "Keanggotaan ruang tidak aktif."}}
    end
  end

  def join("voice:" <> _room_id, _params, _socket) do
    {:error, %{message: "Call diperbarui. Muat ulang halaman sebelum bergabung."}}
  end

  def handle_info(:participants, socket) do
    push(socket, "voice.presence", %{peers: Presence.list(socket)})
    {:noreply, socket}
  end

  def handle_info(
        %Phoenix.Socket.Broadcast{event: "presence_diff", topic: "voice:" <> _},
        socket
      ),
      do: handle_info(:participants, socket)

  def handle_info(:authorize, socket) do
    if authorized?(socket) do
      Process.send_after(self(), :authorize, 5_000)
      {:noreply, socket}
    else
      {:stop, :normal, socket}
    end
  end

  def handle_info(%Phoenix.Socket.Broadcast{event: "room.closed"}, socket),
    do: {:stop, :normal, socket}

  def handle_info(
        %Phoenix.Socket.Broadcast{event: "room.error", payload: %{code: "kicked", member_id: id}},
        socket
      ) do
    if id == socket.assigns.member_id, do: {:stop, :normal, socket}, else: {:noreply, socket}
  end

  def handle_info(_, socket), do: {:noreply, socket}

  def handle_in("voice.mute", %{"muted" => muted}, socket) when is_boolean(muted) do
    Presence.update(socket, socket.assigns.peer_id, &Map.put(&1, :muted, muted))
    {:reply, :ok, assign(socket, :muted, muted)}
  end

  # Fixed 80 ms frames, 16 kHz mono mu-law. Never log microphone payloads.
  def handle_in("voice.audio", %{"pcm" => pcm, "seq" => seq}, socket)
      when is_binary(pcm) and byte_size(pcm) == 1708 and is_integer(seq) and seq >= 0 and
             seq <= 9_007_199_254_740_991 do
    now = System.monotonic_time(:second)
    {window, count} = socket.assigns[:audio_window] || {now, 0}
    count = if window == now, do: count + 1, else: 1
    socket = assign(socket, :audio_window, {now, count})

    cond do
      count > 25 ->
        {:reply, {:error, %{code: "rate_limited"}}, socket}

      socket.assigns.muted ->
        {:reply, :ok, socket}

      seq <= socket.assigns.last_audio_seq ->
        {:reply, :ok, socket}

      true ->
        case Base.decode64(pcm) do
          {:ok, bytes} when byte_size(bytes) == 1280 ->
            broadcast_from!(socket, "voice.audio", %{
              from: socket.assigns.peer_id,
              pcm: pcm,
              seq: seq
            })

            {:reply, :ok, assign(socket, :last_audio_seq, seq)}

          _ ->
            {:reply, {:error, %{code: "invalid_audio"}}, socket}
        end
    end
  end

  def handle_in(_, _, socket),
    do: {:reply, {:error, %{message: "Perintah call tidak valid."}}, socket}

  def handle_out("presence_diff", _payload, socket), do: handle_info(:participants, socket)

  defp authorized?(socket) do
    match?(%{status: "open"}, Repo.get(WatchRooms.Room, socket.assigns.room_id)) and
      not is_nil(WatchRooms.active_member(socket.assigns.room_id, actor(socket)))
  end

  defp actor(socket) do
    %{
      user: socket.assigns.user_id && Accounts.get_user(socket.assigns.user_id),
      guest: socket.assigns.guest_id && Repo.get(Accounts.GuestIdentity, socket.assigns.guest_id)
    }
  end
end
