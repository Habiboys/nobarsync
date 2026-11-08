defmodule NobarSyncWeb.AuthControllerTest do
  use NobarSyncWeb.ConnCase, async: false

  test "register, me, logout, and forbidden admin", %{conn: conn} do
    conn =
      post(conn, "/api/v1/auth/register", %{
        "email" => "person@example.com",
        "password" => "password123",
        "display_name" => "Person"
      })

    assert %{"user" => %{"email" => "person@example.com"}} = json_response(conn, 200)
    csrf = conn.resp_cookies["nobarsync_csrf"].value

    conn =
      conn
      |> recycle()
      |> put_req_header("x-nobarsync-csrf", csrf)
      |> get("/api/v1/auth/me")

    assert %{"user" => %{"display_name" => "Person"}} = json_response(conn, 200)

    forbidden =
      conn
      |> recycle()
      |> put_req_header("x-nobarsync-csrf", csrf)
      |> get("/api/v1/admin/users")

    assert json_response(forbidden, 403)["error"]["code"] == "forbidden"

    logged_out =
      conn
      |> recycle()
      |> put_req_header("x-nobarsync-csrf", csrf)
      |> post("/api/v1/auth/logout")

    assert json_response(logged_out, 200)["ok"]
  end

  test "invalid login and missing fields", %{conn: conn} do
    conn =
      post(conn, "/api/v1/auth/login", %{
        "email" => "missing@example.com",
        "password" => "password123"
      })

    assert json_response(conn, 401)["error"]["code"] == "invalid_credentials"

    conn = post(build_conn(), "/api/v1/auth/register", %{"email" => "bad"})
    assert json_response(conn, 422)["error"]["code"] == "invalid"
  end

  test "guest identity", %{conn: conn} do
    conn = post(conn, "/api/v1/auth/guest", %{"display_name" => "Tamu"})
    assert %{"guest" => %{"display_name" => "Tamu"}} = json_response(conn, 200)
  end
end
