defmodule NobarSync.Analytics.Metrics do
  @moduledoc false
  use GenServer

  def start_link(_), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  @impl true
  def init(_) do
    {:ok, %{drifts: [], buffers: 0, corrections: 0, player_errors: 0, hls_errors: 0}}
  end

  def record_drift(room_id, ms) when is_number(ms) do
    GenServer.cast(__MODULE__, {:drift, room_id, ms})
  end

  def record_drift(_, _), do: :ok

  def record_buffer(_room_id), do: GenServer.cast(__MODULE__, :buffer)
  def record_correction, do: GenServer.cast(__MODULE__, :correction)
  def record_player_error, do: GenServer.cast(__MODULE__, :player_error)
  def record_hls_error, do: GenServer.cast(__MODULE__, :hls_error)

  def snapshot do
    GenServer.call(__MODULE__, :snapshot)
  end

  @impl true
  def handle_cast({:drift, _room_id, ms}, state) do
    drifts = [ms | state.drifts] |> Enum.take(2000)
    {:noreply, %{state | drifts: drifts}}
  end

  def handle_cast(:buffer, state), do: {:noreply, %{state | buffers: state.buffers + 1}}

  def handle_cast(:correction, state),
    do: {:noreply, %{state | corrections: state.corrections + 1}}

  def handle_cast(:player_error, state),
    do: {:noreply, %{state | player_errors: state.player_errors + 1}}

  def handle_cast(:hls_error, state), do: {:noreply, %{state | hls_errors: state.hls_errors + 1}}

  @impl true
  def handle_call(:snapshot, _from, state) do
    sorted = Enum.sort(state.drifts)

    reply = %{
      drift_p50: percentile(sorted, 0.50),
      drift_p95: percentile(sorted, 0.95),
      drift_p99: percentile(sorted, 0.99),
      drift_samples: length(sorted),
      buffer_count: state.buffers,
      correction_count: state.corrections,
      player_errors: state.player_errors,
      hls_errors: state.hls_errors
    }

    {:reply, reply, state}
  end

  defp percentile([], _), do: nil

  defp percentile(sorted, p) do
    index = min(length(sorted) - 1, trunc(p * (length(sorted) - 1)))
    Enum.at(sorted, index)
  end
end
