defmodule NobarSync.RateLimit do
  @moduledoc false
  use GenServer

  def start_link(_), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  @impl true
  def init(_) do
    table = :ets.new(:nobarsync_rate_limit, [:named_table, :public, :set])
    {:ok, table}
  end

  def allow?(key, limit, window_ms) do
    now = System.monotonic_time(:millisecond)

    case :ets.lookup(:nobarsync_rate_limit, key) do
      [{^key, start, count}] when now - start < window_ms and count >= limit ->
        false

      [{^key, start, _count}] when now - start < window_ms ->
        :ets.update_counter(:nobarsync_rate_limit, key, {3, 1})
        true

      _ ->
        :ets.insert(:nobarsync_rate_limit, {key, now, 1})
        true
    end
  end
end
