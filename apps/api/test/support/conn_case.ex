defmodule NobarSyncWeb.ConnCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      import Plug.Conn
      import Phoenix.ConnTest
      import NobarSyncWeb.ConnCase
      alias NobarSync.Repo
      @endpoint NobarSyncWeb.Endpoint
    end
  end

  setup tags do
    NobarSync.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
