defmodule NobarSync.DataCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      alias NobarSync.Repo
      import Ecto
      import Ecto.Query
      import NobarSync.DataCase
    end
  end

  setup tags do
    NobarSync.DataCase.setup_sandbox(tags)
    :ok
  end

  def setup_sandbox(tags) do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(NobarSync.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
  end
end
