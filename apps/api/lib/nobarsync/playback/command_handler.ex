defmodule NobarSync.Playback.CommandHandler do
  @moduledoc false

  alias NobarSync.Playback.Timeline

  @base_lead 1200
  @max_lead 2500

  def lead_ms(rtt_ms, base \\ @base_lead, max_lead \\ @max_lead) do
    adapted = base + div(rtt_ms || 0, 2)
    adapted |> max(base) |> min(max_lead)
  end

  def authorize?(control_mode, role, type) do
    cond do
      role in [:host, :moderator] and type in [:play, :pause, :seek, :change_media, :countdown] ->
        true

      control_mode == :everyone and role == :viewer and type in [:play, :pause, :seek] ->
        true

      true ->
        false
    end
  end

  def activate_due(state, now_mono, now_wall) do
    case state.pending_transition do
      %{effective_at_ms: effective} = pending when now_wall >= effective ->
        activate(state, pending, now_mono, now_wall)

      _ ->
        state
    end
  end

  def drop_future_pending(state, now_mono, now_wall) do
    case state.pending_transition do
      %{effective_at_ms: effective} = pending when now_wall >= effective ->
        activate(state, pending, now_mono, now_wall)

      _ ->
        %{state | pending_transition: nil}
    end
  end

  def schedule(state, command, now_mono, now_wall, lead) do
    revision = state.revision + 1
    effective = now_wall + lead

    pending = %{
      revision: revision,
      kind: command.type,
      countdown: command[:countdown] == true,
      status: next_status(state, command),
      anchor_position_ms: next_position(state, command, now_mono, lead),
      anchor_wall_ms: effective,
      effective_at_ms: effective,
      media_id: next_media_id(state, command),
      duration_ms: next_duration(state, command),
      playback_rate: 1.0
    }

    {:ok,
     %{
       state
       | revision: revision,
         pending_transition: pending,
         media_id: pending.media_id,
         duration_ms: pending.duration_ms
     }, pending}
  end

  def activate(state, pending, now_mono, _now_wall) do
    %{
      state
      | status: pending.status,
        anchor_position_ms: pending.anchor_position_ms,
        anchor_mono_ms: now_mono,
        anchor_wall_ms: pending.anchor_wall_ms,
        playback_rate: pending.playback_rate || 1.0,
        media_id: pending.media_id,
        duration_ms: pending.duration_ms,
        pending_transition: nil,
        revision: pending.revision || state.revision
    }
  end

  defp next_status(_state, %{type: :play}), do: :playing
  defp next_status(_state, %{type: :countdown}), do: :playing
  defp next_status(_state, %{type: :pause}), do: :paused
  defp next_status(_state, %{type: :change_media}), do: :paused

  defp next_status(state, %{type: :seek}) do
    if state.status == :playing, do: :playing, else: :paused
  end

  defp next_position(state, %{type: :seek} = command, _now_mono, _lead) do
    Timeline.clamp(command.position_ms || 0, 0, Timeline.upper(state.duration_ms))
  end

  defp next_position(state, %{type: :play} = command, now_mono, _lead) do
    position =
      if is_integer(command[:position_ms]) and command[:position_ms] >= 0 do
        Timeline.clamp(command[:position_ms], 0, Timeline.upper(state.duration_ms))
      else
        Timeline.position(state, now_mono)
      end

    duration = state.duration_ms || 0
    if duration > 0 and position >= duration - 500, do: 0, else: position
  end

  defp next_position(_state, %{type: :change_media}, _now_mono, _lead), do: 0

  defp next_position(state, %{type: :pause} = command, now_mono, lead) do
    if is_integer(command[:position_ms]) and command[:position_ms] >= 0 do
      Timeline.clamp(command[:position_ms], 0, Timeline.upper(state.duration_ms))
    else
      case state.status do
        :playing -> Timeline.position(state, now_mono + lead)
        _ -> Timeline.position(state, now_mono)
      end
    end
  end

  defp next_position(state, _command, now_mono, _lead), do: Timeline.position(state, now_mono)

  defp next_media_id(_state, %{type: :change_media, media_id: id}), do: id
  defp next_media_id(state, _), do: state.media_id

  defp next_duration(_state, %{type: :change_media, duration_ms: duration}), do: duration || 0
  defp next_duration(state, _), do: state.duration_ms || 0
end
