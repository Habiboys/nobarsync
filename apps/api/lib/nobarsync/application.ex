defmodule NobarSync.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = children(Application.get_env(:nobarsync, :role, "all"))
    Supervisor.start_link(children, strategy: :one_for_one, name: NobarSync.Supervisor)
  end

  defp children(role) do
    base = [
      NobarSyncWeb.Telemetry,
      NobarSync.Repo,
      {Phoenix.PubSub, name: NobarSync.PubSub},
      NobarSyncWeb.Presence,
      NobarSync.RateLimit,
      NobarSync.Analytics.Metrics,
      {Registry, keys: :unique, name: NobarSync.Playback.Registry},
      {Oban, Application.fetch_env!(:nobarsync, Oban)}
    ]

    coordinators =
      if role in ["api", "all", nil] do
        [
          NobarSync.Playback.CoordinatorSupervisor,
          NobarSync.Media.ProgressListener
        ]
      else
        []
      end

    base ++ coordinators ++ [NobarSyncWeb.Endpoint]
  end

  @impl true
  def config_change(changed, _new, removed) do
    NobarSyncWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
