defmodule NobarSyncWeb.VoiceChannelTest do
  use NobarSyncWeb.ChannelCase, async: false
  alias NobarSync.{Accounts, WatchRooms}
  alias NobarSyncWeb.UserSocket

  setup do
    {:ok, user} =
      Accounts.register_user(%{
        "email" => "voice-#{System.unique_integer([:positive])}@example.com",
        "password" => "password123",
        "display_name" => "Voice user"
      })

    {:ok, %{room: room}} = WatchRooms.create_room(user, %{"title" => "Voice relay"})

    token =
      Phoenix.Token.sign(NobarSyncWeb.Endpoint, "socket", %{user_id: user.id, guest_id: nil})

    {:ok, socket} = connect(UserSocket, %{"token" => token})
    %{room: room, socket: socket}
  end

  test "starts muted, then relays frames with server identity and drops replay", %{
    room: room,
    socket: socket
  } do
    {:ok, reply, socket} =
      subscribe_and_join(socket, "voice:#{room.id}", %{"transport" => "websocket-v2"})

    peer_id = reply.peer_id
    frame = Base.encode64(:binary.copy(<<200>>, 1280))
    ref = push(socket, "voice.audio", %{"pcm" => frame, "seq" => 0, "from" => "spoof"})
    assert_reply ref, :ok
    refute_broadcast "voice.audio", _
    ref = push(socket, "voice.mute", %{"muted" => false})
    assert_reply ref, :ok
    ref = push(socket, "voice.audio", %{"pcm" => frame, "seq" => 0, "from" => "spoof"})
    assert_reply ref, :ok
    assert_broadcast "voice.audio", %{from: ^peer_id, pcm: ^frame, seq: 0}
    ref = push(socket, "voice.audio", %{"pcm" => frame, "seq" => 0})
    assert_reply ref, :ok
    refute_broadcast "voice.audio", _
    ref = push(socket, "voice.mute", %{"muted" => true})
    assert_reply ref, :ok
    ref = push(socket, "voice.audio", %{"pcm" => frame, "seq" => 1})
    assert_reply ref, :ok
    refute_broadcast "voice.audio", _
  end

  test "rejects malformed audio and stale clients", %{room: room, socket: socket} do
    assert {:error, %{message: _}} = subscribe_and_join(socket, "voice:#{room.id}", %{})

    {:ok, _, socket} =
      subscribe_and_join(socket, "voice:#{room.id}", %{"transport" => "websocket-v2"})

    ref = push(socket, "voice.mute", %{"muted" => false})
    assert_reply ref, :ok
    ref = push(socket, "voice.audio", %{"pcm" => String.duplicate("!", 1708), "seq" => 0})
    assert_reply ref, :error, %{code: "invalid_audio"}
  end

  test "limits audio flood and refuses non-members", %{room: room, socket: socket} do
    {:ok, _, socket} =
      subscribe_and_join(socket, "voice:#{room.id}", %{"transport" => "websocket-v2"})

    frame = Base.encode64(:binary.copy(<<255>>, 1280))
    # Pin this channel's window so the limit check is independent of second boundaries.
    :sys.replace_state(socket.channel_pid, fn state ->
      Phoenix.Socket.assign(state, :audio_window, {System.monotonic_time(:second), 25})
    end)

    ref = push(socket, "voice.audio", %{"pcm" => frame, "seq" => 1})
    assert_reply ref, :error, %{code: "rate_limited"}
    outsider = socket(UserSocket, "outsider", %{user_id: nil, guest_id: nil})

    assert {:error, _} =
             subscribe_and_join(outsider, "voice:#{room.id}", %{"transport" => "websocket-v2"})
  end
end
