defmodule NobarSync.Media.ProgressListener do
  @moduledoc false
  use GenServer

  alias NobarSync.Playback.Broadcaster

  def start_link(_), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  def notify(payload) when is_map(payload) do
    NobarSync.Repo.query("SELECT pg_notify('media_progress', $1)", [Jason.encode!(payload)])
  end

  @impl true
  def init(_) do
    config =
      NobarSync.Repo.config()
      |> Keyword.drop([
        :pool,
        :pool_size,
        :telemetry_prefix,
        :telemetry_event,
        :stacktrace,
        :show_sensitive_data_on_connection_error,
        :log
      ])

    {:ok, pid} = Postgrex.Notifications.start_link(config)
    {:ok, _ref} = Postgrex.Notifications.listen(pid, "media_progress")
    {:ok, pid}
  end

  @impl true
  def handle_info({:notification, _pid, _ref, "media_progress", payload}, state) do
    case Jason.decode(payload) do
      {:ok, %{"owner_id" => owner_id} = data} when is_binary(owner_id) ->
        Broadcaster.broadcast("user:#{owner_id}", "media.progress", data)

      _ ->
        :ok
    end

    {:noreply, state}
  end

  def handle_info(_, state), do: {:noreply, state}
end
