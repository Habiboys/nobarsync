defmodule NobarSync.Playback.CommandHandlerTest do
  use ExUnit.Case, async: true

  alias NobarSync.Playback.CommandHandler

  setup do
    state = %{
      revision: 4,
      status: :paused,
      anchor_position_ms: 1_000,
      anchor_mono_ms: 0,
      anchor_wall_ms: 10_000,
      playback_rate: 1.0,
      media_id: "m",
      duration_ms: 20_000,
      pending_transition: nil,
      control_mode: :host_only
    }

    {:ok, state: state}
  end

  test "lead time adapts to rtt and stays inside the cap" do
    assert CommandHandler.lead_ms(0) == 200
    assert CommandHandler.lead_ms(400) == 400
    assert CommandHandler.lead_ms(10_000) == 400
  end

  test "viewer cannot control a host-only room", %{state: state} do
    refute CommandHandler.authorize?(state.control_mode, :viewer, :play)
    assert CommandHandler.authorize?(:everyone, :viewer, :seek)
    refute CommandHandler.authorize?(:everyone, :viewer, :change_media)
    assert CommandHandler.authorize?(:host_only, :host, :pause)
  end

  test "a newer command supersedes a pending transition", %{state: state} do
    {:ok, scheduled, pending} = CommandHandler.schedule(state, %{type: :play}, 0, 10_000, 1_200)
    assert scheduled.revision == 5
    assert pending.status == :playing
    assert scheduled.pending_transition.effective_at_ms == 11_200

    dropped = CommandHandler.drop_future_pending(scheduled, 100, 10_100)

    {:ok, again, _} =
      CommandHandler.schedule(dropped, %{type: :seek, position_ms: 50_000}, 100, 10_100, 1_200)

    assert again.revision == 6
    assert again.pending_transition.anchor_position_ms == 20_000
    assert again.pending_transition.status == :paused
  end

  test "pause predicts the position at the effective time" do
    state = %{
      revision: 1,
      status: :playing,
      anchor_position_ms: 0,
      anchor_mono_ms: 0,
      anchor_wall_ms: 0,
      playback_rate: 1.0,
      media_id: "m",
      duration_ms: 30_000,
      pending_transition: nil
    }

    {:ok, _, pending} = CommandHandler.schedule(state, %{type: :pause}, 5_000, 5_000, 1_200)
    assert pending.anchor_position_ms == 6_200
    assert pending.status == :paused
  end

  test "old revision is not applied after a newer one is active", %{state: state} do
    {:ok, scheduled, first} = CommandHandler.schedule(state, %{type: :play}, 0, 0, 100)
    activated = CommandHandler.activate(scheduled, first, 100, 100)
    assert activated.status == :playing
    assert activated.pending_transition == nil
    assert activated.revision == 5
  end
end
