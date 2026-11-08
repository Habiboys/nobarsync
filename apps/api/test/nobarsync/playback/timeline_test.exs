defmodule NobarSync.Playback.TimelineTest do
  use ExUnit.Case, async: true

  alias NobarSync.Playback.Timeline

  test "playing position follows elapsed server time and rate" do
    state = %{
      status: :playing,
      anchor_position_ms: 600_000,
      anchor_mono_ms: 1_000,
      playback_rate: 1.0,
      duration_ms: 7_200_000
    }

    assert Timeline.position(state, 6_000) == 605_000
  end

  test "paused position stays frozen" do
    state = %{
      status: :paused,
      anchor_position_ms: 1000,
      anchor_mono_ms: 0,
      playback_rate: 1.0,
      duration_ms: 5000
    }

    assert Timeline.position(state, 9_000) == 1000
  end

  test "position is clipped to duration" do
    state = %{
      status: :playing,
      anchor_position_ms: 4_000,
      anchor_mono_ms: 0,
      playback_rate: 2.0,
      duration_ms: 5_000
    }

    assert Timeline.position(state, 2_000) == 5_000
  end

  test "negative elapsed does not go below zero" do
    state = %{
      status: :playing,
      anchor_position_ms: 100,
      anchor_mono_ms: 5_000,
      playback_rate: 1.0,
      duration_ms: 5_000
    }

    assert Timeline.position(state, 0) == 0
  end

  test "wall clock recovery uses the same formula" do
    state = %{
      status: :playing,
      anchor_position_ms: 0,
      anchor_wall_ms: 1_000,
      playback_rate: 1.0,
      duration_ms: 10_000
    }

    assert Timeline.position_from_wall(state, 4_000) == 3_000
  end
end
