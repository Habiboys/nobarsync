defmodule NobarSyncWeb.HealthControllerTest do
  use NobarSyncWeb.ConnCase, async: false

  test "live and ready", %{conn: conn} do
    assert json_response(get(conn, "/health/live"), 200)["status"] == "ok"
    assert json_response(get(conn, "/health/ready"), 200)["status"] == "ok"
  end
end
