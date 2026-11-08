defmodule NobarSync.Playback.StatePersistence do
  @moduledoc false

  alias NobarSync.Playback.{Snapshot, Timeline}
  alias NobarSync.Repo
  alias NobarSync.WatchRooms.Room

  def restore(room_id) do
    room = Repo.get!(Room, room_id)
    snapshot = Repo.get(Snapshot, room_id)
    now_mono = System.monotonic_time(:millisecond)
    now_wall = System.os_time(:millisecond)

    base = %{
      room_id: room_id,
      media_id: room.media_asset_id,
      revision: 0,
      status: :idle,
      anchor_position_ms: 0,
      anchor_mono_ms: now_mono,
      anchor_wall_ms: now_wall,
      playback_rate: 1.0,
      effective_at_ms: nil,
      pending_transition: nil,
      duration_ms: 0,
      control_mode: mode(room.control_mode, :host_only),
      buffering_mode: mode(room.buffering_mode, :independent),
      updated_at: DateTime.utc_now(),
      request_ids: %{},
      timer_ref: nil,
      members: %{},
      paused_by_buffer: false,
      buffer_since: nil,
      host_absent_since: nil,
      fencing_token: nil
    }

    if snapshot do
      status = status_atom(snapshot.status)

      restored = %{
        base
        | media_id: snapshot.media_asset_id || room.media_asset_id,
          revision: snapshot.revision,
          status: status,
          anchor_position_ms: snapshot.anchor_position_ms,
          anchor_wall_ms: snapshot.anchor_wall_ms,
          playback_rate: snapshot.playback_rate || 1.0,
          duration_ms: snapshot.duration_ms || 0,
          control_mode: mode(snapshot.control_mode || room.control_mode, :host_only),
          buffering_mode: mode(snapshot.buffering_mode || room.buffering_mode, :independent)
      }

      if status == :playing do
        position = Timeline.position_from_wall(restored, now_wall)
        ended? = restored.duration_ms > 0 and position >= restored.duration_ms

        %{
          restored
          | status: if(ended?, do: :ended, else: :playing),
            anchor_position_ms: position,
            anchor_mono_ms: now_mono,
            anchor_wall_ms: now_wall
        }
      else
        %{restored | anchor_mono_ms: now_mono}
      end
    else
      base
    end
  end

  def save(state) do
    pending = state.pending_transition

    attrs = %{
      room_id: state.room_id,
      revision: state.revision,
      media_asset_id: (pending && pending.media_id) || state.media_id,
      status: Atom.to_string(state.status),
      anchor_position_ms: state.anchor_position_ms,
      anchor_wall_ms: state.anchor_wall_ms,
      playback_rate: state.playback_rate * 1.0,
      effective_at_ms: state.pending_transition && state.pending_transition.effective_at_ms,
      duration_ms: state.duration_ms || 0,
      control_mode: Atom.to_string(state.control_mode),
      buffering_mode: Atom.to_string(state.buffering_mode)
    }

    %Snapshot{room_id: state.room_id}
    |> Ecto.Changeset.change(Map.delete(attrs, :room_id))
    |> Repo.insert(
      on_conflict: {:replace_all_except, [:room_id, :inserted_at]},
      conflict_target: :room_id
    )
  end

  defp status_atom("playing"), do: :playing
  defp status_atom("paused"), do: :paused
  defp status_atom("ended"), do: :ended
  defp status_atom(_), do: :idle

  defp mode("everyone", _), do: :everyone
  defp mode("host_only", _), do: :host_only
  defp mode("pause_all", _), do: :pause_all
  defp mode("host_decides", _), do: :host_decides
  defp mode("independent", _), do: :independent
  defp mode(_, default), do: default

  def save_event(state, command) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    %NobarSync.Playback.Event{}
    |> Ecto.Changeset.change(%{
      room_id: state.room_id,
      revision: state.revision,
      request_id: command[:request_id],
      actor_member_id: command[:member_id],
      type: Atom.to_string(command.type),
      payload: %{
        "position_ms" => command[:position_ms],
        "media_id" => command[:media_id]
      },
      inserted_at: now
    })
    |> Repo.insert()
  end
end
