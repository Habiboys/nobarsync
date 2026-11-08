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
      Phoenix.Token.sign(NobarSyncWeb.Endpoint, "socket", %{user_id: viewer.id, guest_id: nil})

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
end
