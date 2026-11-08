defmodule NobarSync.Playback.BufferingPolicy do
  @moduledoc false

  def decide(mode, members, opts \\ []) do
    min_affected = Keyword.get(opts, :min_affected, 2)
    ratio = Keyword.get(opts, :ratio, 0.3)
    paused_by_buffer = Keyword.get(opts, :paused_by_buffer, false)

    online = Enum.filter(members, &(&1.online != false))
    total = length(online)
    buffering = Enum.count(online, &(&1.buffering == true))

    cond do
      mode != :pause_all -> :none
      total == 0 -> :none
      buffering >= min_affected and buffering / total >= ratio -> :pause
      paused_by_buffer and buffering == 0 -> :resume
      true -> :none
    end
  end
end
