defmodule NobarSyncWeb.ChannelCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      import Phoenix.ChannelTest
      import NobarSyncWeb.ChannelCase
      alias NobarSync.Repo
      @endpoint NobarSyncWeb.Endpoint
    end
  end

  setup tags do
    NobarSync.DataCase.setup_sandbox(tags)
    :ok
  end
end
