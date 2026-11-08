defmodule NobarSync.Playback.BufferingPolicyTest do
  use ExUnit.Case, async: true

  alias NobarSync.Playback.BufferingPolicy

  test "independent mode never pauses the room" do
    members = [%{online: true, buffering: true}, %{online: true, buffering: true}]
    assert BufferingPolicy.decide(:independent, members) == :none
  end

  test "pause_all waits for the threshold" do
    one = [%{online: true, buffering: true}, %{online: true, buffering: false}]
    assert BufferingPolicy.decide(:pause_all, one) == :none

    enough = [%{online: true, buffering: true}, %{online: true, buffering: true}]
    assert BufferingPolicy.decide(:pause_all, enough) == :pause
  end

  test "resume only after a buffer pause when nobody is buffering" do
    members = [%{online: true, buffering: false}, %{online: true, buffering: false}]
    assert BufferingPolicy.decide(:pause_all, members, paused_by_buffer: true) == :resume
    assert BufferingPolicy.decide(:host_decides, members, paused_by_buffer: true) == :none
  end
end
