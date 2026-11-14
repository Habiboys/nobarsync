defmodule NobarSyncWeb.RoomChannelTest do
  use NobarSyncWeb.ChannelCase, async: false

  alias NobarSync.Accounts
  alias NobarSync.WatchRooms
  alias NobarSyncWeb.UserSocket

  setup do
    {:ok, user} =
      Accounts.register_user(%{
        "email" => "channel-#{System.unique_integer()}@example.com",
        "password" => "password123",
        "display_name" => "Host"
      })

    {:ok, %{room: room}} =
      WatchRooms.create_room(user, %{"title" => "Kanal", "visibility" => "public"})

    {:ok, viewer} =
      Accounts.register_user(%{
        "email" => "viewer-#{System.unique_integer()}@example.com",
        "password" => "password123",
        "display_name" => "Viewer"
      })

    {:ok, _} = WatchRooms.join(room, %{user: viewer, guest: nil}, nil)

    token =
      Phoenix.Token.sign(NobarSyncWeb.Endpoint, "socket", Accounts.socket_claims(viewer))

    {:ok, socket} = connect(UserSocket, %{"token" => token})
    %{socket: socket, room: room}
  end

  test "join returns a snapshot and a viewer cannot play", %{socket: socket, room: room} do
    {:ok, snapshot, socket} = subscribe_and_join(socket, "room:#{room.id}", %{})
    assert snapshot.revision == 0
    assert snapshot.state.status == :idle
    ref = push(socket, "playback.play", %{"request_id" => "viewer-play", "rtt_ms" => 0})
    assert_reply ref, :error, %{code: "forbidden"}
  end

  test "room detail keeps people who are connected to the player", %{socket: socket, room: room} do
    {:ok, _, socket} = subscribe_and_join(socket, "room:#{room.id}", %{})
    assert_push "room.presence", _
    assert [%{display_name: "Viewer"}] = NobarSyncWeb.LiveBoard.people(room.id)
    assert length(WatchRooms.list_members(room.id)) == 2
    connected = NobarSyncWeb.LiveBoard.admin()
    watching = Enum.find(connected.people, &(&1.room_code == room.code))
    assert watching.display_name == "Viewer"
    assert Enum.find(connected.rooms, &(&1.code == room.code)).online

    Process.unlink(socket.channel_pid)
    ref = leave(socket)
    assert_reply ref, :ok
    await_departure(room.id)

    assert NobarSyncWeb.LiveBoard.people(room.id) == []
    assert length(WatchRooms.list_members(room.id)) == 2
    board = NobarSyncWeb.LiveBoard.admin()
    listed = Enum.find(board.rooms, &(&1.code == room.code))
    assert listed.online == false
    assert listed.playback.status == "idle"
    assert listed.playback.position_ms == 0
  end

  test "clock ping echoes the client sample", %{socket: socket, room: room} do
    {:ok, _, socket} = subscribe_and_join(socket, "room:#{room.id}", %{})
    ref = push(socket, "clock.ping", %{"t0" => 12.5})
    assert_reply ref, :ok, %{t0: 12.5, server_wall_ms: wall} when is_integer(wall)
  end

  test "legacy guest tokens and memberships cannot enter rooms", %{room: room} do
    {:ok, result} = Accounts.create_guest("Legacy guest")

    token =
      Phoenix.Token.sign(NobarSyncWeb.Endpoint, "socket", %{
        user_id: nil,
        guest_id: result.guest.id
      })

    assert :error = connect(UserSocket, %{"token" => token})
    actor = %{user: nil, guest: result.guest}
    assert {:error, :unauthorized} = WatchRooms.join(room, actor, nil)
    assert is_nil(WatchRooms.active_member(room.id, actor))
  end

  test "admin monitoring reads authoritative film and timeline without joining", %{
    room: room,
    socket: socket
  } do
    user = Accounts.get_user(socket.assigns.user_id)

    {:ok, film} =
      NobarSync.Media.create_youtube(user, %{
        "url" => "https://youtu.be/aqz-KE-bpKQ",
        "title" => "Film uji waktu"
      })

    {:ok, pid} = NobarSync.Playback.RoomCoordinator.ensure_started(room.id)
    now = System.os_time(:millisecond)

    :sys.replace_state(pid, fn state ->
      Map.merge(state, %{
        media_id: film.id,
        duration_ms: 600_000,
        status: :playing,
        anchor_position_ms: 120_000,
        anchor_wall_ms: now - 3000,
        anchor_mono_ms: System.monotonic_time(:millisecond) - 3000
      })
    end)

    monitored = Enum.find(NobarSyncWeb.LiveBoard.admin().rooms, &(&1.id == room.id))
    assert monitored.media_title == "Film uji waktu"
    assert monitored.playback.status == "playing"
    assert monitored.playback.position_ms >= 123_000 and monitored.playback.position_ms < 125_000
    assert monitored.playback.duration_ms == 600_000
    assert monitored.people == []

    :sys.replace_state(pid, fn state ->
      %{state | status: :paused, anchor_position_ms: 125_000}
    end)

    assert Enum.find(NobarSyncWeb.LiveBoard.admin().rooms, &(&1.id == room.id)).playback.position_ms ==
             125_000

    NobarSync.Playback.RoomCoordinator.stop(room.id)
  end

  test "online accounts include non-watch pages and hide query strings", %{socket: socket} do
    id = socket.assigns.user_id
    {:ok, _, own} = subscribe_and_join(socket, "user:#{id}", %{})
    ref = push(own, "activity.page", %{"page" => "/library"})
    assert_reply ref, :ok
    user = Enum.find(NobarSyncWeb.LiveBoard.admin().users, &(&1.id == id))
    assert user.tabs == 1
    assert user.pages == ["/library"]
    ref = push(own, "activity.page", %{"page" => "/library?secret=hidden"})
    assert_reply ref, :ok
    assert Enum.find(NobarSyncWeb.LiveBoard.admin().users, &(&1.id == id)).pages == ["/library"]
    assert {:error, %{code: "forbidden"}} = subscribe_and_join(socket, "observe:admin", %{})
  end

  test "room observers see updates without being counted as participants", %{
    socket: socket,
    room: room
  } do
    {:ok, _, observer} = subscribe_and_join(socket, "observe:room:#{room.code}", %{})
    NobarSync.Playback.Broadcaster.broadcast("room:#{room.id}", "presence_diff", %{})
    assert_push "activity.changed", %{}, 500
    assert NobarSyncWeb.LiveBoard.people(room.id) == []
    Process.unlink(observer.channel_pid)
    ref = leave(observer)
    assert_reply ref, :ok
  end

  test "explicit room leave closes the player's channel even when tab remains open", %{
    socket: socket,
    room: room
  } do
    {:ok, _, joined} = subscribe_and_join(socket, "room:#{room.id}", %{})
    assert_push "room.presence", _
    user = Accounts.get_user(socket.assigns.user_id)
    {:ok, member} = WatchRooms.leave(room, %{user: user, guest: nil})
    assert NobarSyncWeb.LiveBoard.people(room.id) == []
    Process.unlink(joined.channel_pid)
    ref = Process.monitor(joined.channel_pid)

    NobarSync.Playback.Broadcaster.broadcast("room:#{room.id}", "room.member_left", %{
      member_id: member.id
    })

    assert_push "room.error", %{code: "left"}
    assert_receive {:DOWN, ^ref, :process, _, :normal}
    assert NobarSyncWeb.Presence.list("room:#{room.id}") == %{}
  end

  test "chat supports reply, edit, delete, reactions, pin, and authorization", %{
    socket: viewer_socket,
    room: room
  } do
    host = Accounts.get_user(room.host_user_id)

    host_token =
      Phoenix.Token.sign(NobarSyncWeb.Endpoint, "socket", Accounts.socket_claims(host))

    {:ok, host_socket} = connect(UserSocket, %{"token" => host_token})
    {:ok, _, host_channel} = subscribe_and_join(host_socket, "room:#{room.id}", %{})
    {:ok, _, viewer_channel} = subscribe_and_join(viewer_socket, "room:#{room.id}", %{})

    ref = push(host_channel, "chat.send", %{"body" => "Halo semua"})
    assert_reply ref, :ok, host_msg
    assert host_msg.body == "Halo semua"
    assert_broadcast "chat.message", %{id: host_msg_id, body: "Halo semua"}
    assert host_msg_id == host_msg.id

    # Viewer replies to host's message
    ref =
      push(viewer_channel, "chat.send", %{
        "body" => "Halo juga!",
        "reply_to_id" => host_msg.id
      })

    assert_reply ref, :ok, reply_msg
    assert reply_msg.reply_to.id == host_msg.id
    assert reply_msg.reply_to.body == "Halo semua"

    # Viewer cannot edit host's message
    ref = push(viewer_channel, "chat.edit", %{"id" => host_msg.id, "body" => "Diubah orang"})
    assert_reply ref, :error, %{code: "forbidden"}

    # Viewer edits own message
    ref = push(viewer_channel, "chat.edit", %{"id" => reply_msg.id, "body" => "Halo kak!"})
    assert_reply ref, :ok, edited_msg
    assert edited_msg.body == "Halo kak!"
    assert edited_msg.edited_at != nil
    assert_broadcast "chat.edited", %{id: edited_id, body: "Halo kak!"}
    assert edited_id == reply_msg.id

    # Viewer toggles reaction on host's message
    ref = push(viewer_channel, "chat.react", %{"id" => host_msg.id, "emoji" => "👍"})
    assert_reply ref, :ok
    assert_broadcast "chat.reacted", %{id: reacted_id, reactions: [%{emoji: "👍", count: 1}]}
    assert reacted_id == host_msg.id

    ref = push(viewer_channel, "chat.react", %{"id" => host_msg.id, "emoji" => "👍"})
    assert_reply ref, :ok
    assert_broadcast "chat.reacted", %{id: ^reacted_id, reactions: []}

    # Viewer cannot pin, host can pin
    ref = push(viewer_channel, "chat.pin", %{"id" => host_msg.id, "pinned" => true})
    assert_reply ref, :error, %{code: "forbidden"}

    ref = push(host_channel, "chat.pin", %{"id" => host_msg.id, "pinned" => true})
    assert_reply ref, :ok
    assert_broadcast "chat.pinned", %{message: %{id: ^host_msg_id}}

    # Viewer cannot delete host's message, host can delete viewer's message
    ref = push(viewer_channel, "chat.delete", %{"id" => host_msg.id})
    assert_reply ref, :error, %{code: "forbidden"}

    ref = push(host_channel, "chat.delete", %{"id" => reply_msg.id})
    assert_reply ref, :ok
    assert_broadcast "chat.deleted", %{id: deleted_id}
    assert deleted_id == reply_msg.id

    # Host deletes own message; replies to it show deleted placeholder and listing omits deleted
    ref =
      push(viewer_channel, "chat.send", %{
        "body" => "Balas pesan yang akan dihapus",
        "reply_to_id" => host_msg.id
      })

    assert_reply ref, :ok, dangling_reply
    ref = push(host_channel, "chat.delete", %{"id" => host_msg.id})
    assert_reply ref, :ok

    {messages, _has_more} = NobarSync.Messaging.list_messages_page(room.id)
    serialized = Enum.map(messages, &NobarSync.Messaging.serialize_message/1)
    assert Enum.map(serialized, & &1.id) == [dangling_reply.id]
    assert hd(serialized).reply_to.deleted == true
    assert hd(serialized).reply_to.body == ""
    assert is_nil(NobarSync.Messaging.get_pinned_message(room.id))
  end

  defp await_departure(room_id, attempts \\ 20)

  defp await_departure(room_id, 0) do
    flunk("presence still lists #{inspect(NobarSyncWeb.LiveBoard.people(room_id))}")
  end

  defp await_departure(room_id, attempts) do
    if NobarSyncWeb.LiveBoard.people(room_id) == [] do
      :ok
    else
      Process.sleep(50)
      await_departure(room_id, attempts - 1)
    end
  end
end
