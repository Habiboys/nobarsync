defmodule NobarSync.Playback.Timeline do
  @moduledoc false

  @unknown_ceiling_ms 86_400_000

  def clamp(_value, min_value, max_value) when min_value > max_value, do: min_value

  def clamp(value, min_value, max_value) do
    value |> max(min_value) |> min(max_value)
  end

  def position(state, now_mono) when is_integer(now_mono) do
    duration = upper(state.duration_ms)
    anchor = state.anchor_position_ms || 0

    case state.status do
      :playing ->
        elapsed = now_mono - (state.anchor_mono_ms || now_mono)
        rate = state.playback_rate || 1.0
        clamp(anchor + trunc(elapsed * rate), 0, duration)

      :ended ->
        upper(state.duration_ms)

      _ ->
        clamp(anchor, 0, duration)
    end
  end

  def position_from_wall(state, now_wall) when is_integer(now_wall) do
    duration = upper(state.duration_ms)
    anchor = state.anchor_position_ms || 0

    case state.status do
      :playing ->
        elapsed = now_wall - (state.anchor_wall_ms || now_wall)
        rate = state.playback_rate || 1.0
        clamp(anchor + trunc(elapsed * rate), 0, duration)

      :ended ->
        upper(state.duration_ms)

      _ ->
        clamp(anchor, 0, duration)
    end
  end

  def upper(nil), do: @unknown_ceiling_ms
  def upper(0), do: @unknown_ceiling_ms
  def upper(value) when is_integer(value) and value > 0, do: value
  def upper(_), do: @unknown_ceiling_ms
end
