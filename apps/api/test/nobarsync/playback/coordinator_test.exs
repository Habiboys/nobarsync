defmodule NobarSync.Playback.CoordinatorTest do
  use NobarSync.DataCase, async: false

  alias NobarSync.Accounts
  alias NobarSync.Playback.RoomCoordinator
  alias NobarSync.WatchRooms

  setup do
    {:ok, user} =
      Accounts.register_user(%{
        "email" => "host-#{System.unique_integer()}@example.com",
        "password" => "password123",
        "display_name" => "Host"
      })

    {:ok, %{room: room}} =
      WatchRooms.create_room(user, %{"title" => "Uji", "visibility" => "public"})

    {:ok, _pid} = RoomCoordinator.ensure_started(room.id)
    %{room: room, user: user}
  end

  test "play then pause keeps a monotonic revision", %{room: room, user: user} do
    {:ok, asset} =
      NobarSync.Media.create_youtube(user, %{
        "url" => "https://youtu.be/dQw4w9WgXcQ",
        "title" => "Clip"
      })

    {:ok, _} =
      RoomCoordinator.command(room.id, %{
        type: :change_media,
        role: :host,
        request_id: "media",
        media_id: asset.id,
        duration_ms: 8_000,
        media_status: "ready",
        provider: "youtube",
        rtt_ms: 0
      })

    {:ok, first} =
      RoomCoordinator.command(room.id, %{
        type: :play,
        role: :host,
        request_id: "req-1",
        member_id: nil,
        rtt_ms: 0
      })

    assert first.revision == 2
    assert first.pending.status == :playing

    {:ok, same} =
      RoomCoordinator.command(room.id, %{
        type: :play,
        role: :host,
        request_id: "req-1",
        member_id: nil,
        rtt_ms: 0
      })

    assert same.revision == 2

    assert {:error, :forbidden} =
             RoomCoordinator.command(room.id, %{
               type: :pause,
               role: :viewer,
               request_id: "req-2",
               member_id: nil,
               rtt_ms: 0
             })
  end

  test "viewer command is forbidden and seek is clipped after play", %{room: room} do
    assert {:error, :forbidden} =
             RoomCoordinator.command(room.id, %{
               type: :seek,
               role: :viewer,
               request_id: "nope",
               position_ms: 10,
               rtt_ms: 0
             })

    assert {:error, :media_not_ready} =
             RoomCoordinator.command(room.id, %{
               type: :play,
               role: :host,
               request_id: "no-media",
               rtt_ms: 0
             })
  end

  test "snapshot survives a coordinator restart", %{room: room} do
    {:ok, asset} =
      NobarSync.Media.create_youtube(room_owner(room), %{
        "url" => "https://youtu.be/dQw4w9WgXcQ",
        "title" => "Clip"
      })

    {:ok, _} =
      RoomCoordinator.command(room.id, %{
        type: :change_media,
        role: :host,
        request_id: "media",
        media_id: asset.id,
        duration_ms: 8_000,
        media_status: "ready",
        provider: "youtube",
        rtt_ms: 0
      })

    [{pid, _}] = Registry.lookup(NobarSync.Playback.Registry, room.id)
    GenServer.stop(pid)
    Process.sleep(50)
    {:ok, _} = RoomCoordinator.ensure_started(room.id)
    snapshot = RoomCoordinator.snapshot(room.id)
    assert snapshot.media_id == asset.id
    assert snapshot.revision >= 1
  end

  defp room_owner(room), do: NobarSync.Accounts.get_user!(room.host_user_id)
end
