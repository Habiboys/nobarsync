defmodule NobarSyncWeb.MediaControllerTest do
  use NobarSyncWeb.ConnCase, async: false
  alias NobarSync.{Accounts, Media}

  setup %{conn: conn} do
    {:ok, user} =
      Accounts.register_user(%{
        "email" => "media-route-#{System.unique_integer([:positive])}@example.com",
        "display_name" => "Uji route",
        "password" => "password123"
      })

    conn = post(conn, "/api/v1/auth/login", %{"email" => user.email, "password" => "password123"})
    assert json_response(conn, 200)["user"]["id"] == user.id
    csrf = conn.resp_cookies["nobarsync_csrf"].value

    {:ok, film} =
      Media.create_youtube(user, %{
        "url" => "https://youtu.be/aqz-KE-bpKQ",
        "title" => "Film route"
      })

    %{conn: recycle(conn) |> put_req_header("x-nobarsync-csrf", csrf), film: film}
  end

  test "GET import endpoint gives method guidance instead of querying a UUID", %{conn: conn} do
    conn = get(conn, "/api/v1/media/import-url")
    assert json_response(conn, 405)["error"]["code"] == "method_not_allowed"
    assert get_resp_header(conn, "allow") == ["POST"]
  end

  test "invalid and nonexistent IDs return JSON 404 across media operations", %{conn: conn} do
    for id <- ["not-a-uuid", Ecto.UUID.generate()] do
      for {method, path, body} <- [
            {:get, "/api/v1/media/#{id}", nil},
            {:get, "/api/v1/media/#{id}/processing", nil},
            {:patch, "/api/v1/media/#{id}", %{"title" => "Nol"}},
            {:delete, "/api/v1/media/#{id}", nil},
            {:post, "/api/v1/media/#{id}/subtitles", %{}}
          ] do
        response =
          dispatch(
            recycle(conn)
            |> put_req_header(
              "x-nobarsync-csrf",
              conn.req_headers
              |> Enum.find_value(fn {key, value} -> if key == "x-nobarsync-csrf", do: value end)
            ),
            @endpoint,
            method,
            path,
            body
          )

        assert json_response(response, 404)["error"]["code"] == "not_found"
      end
    end

    assert Media.get_asset(nil) == nil
    assert Media.get_asset(%{}) == nil
  end

  test "valid film details and ownership authorization are preserved", %{conn: conn, film: film} do
    assert json_response(get(conn, "/api/v1/media/#{film.id}"), 200)["media"]["title"] ==
             "Film route"

    {:ok, owner} =
      Accounts.register_user(%{
        "email" => "other-owner-#{System.unique_integer([:positive])}@example.com",
        "display_name" => "Lain",
        "password" => "password123"
      })

    {:ok, private} = Media.create_youtube(owner, %{"url" => "https://youtu.be/aqz-KE-bpKQ"})

    assert json_response(get(recycle(conn), "/api/v1/media/#{private.id}"), 403)["error"]["code"] ==
             "forbidden"
  end

  test "POST still performs source validation and requires login", %{conn: conn} do
    previous = System.get_env("IMPORT_HOST_ALLOWLIST")
    System.put_env("IMPORT_HOST_ALLOWLIST", "")

    on_exit(fn ->
      if previous,
        do: System.put_env("IMPORT_HOST_ALLOWLIST", previous),
        else: System.delete_env("IMPORT_HOST_ALLOWLIST")
    end)

    response =
      post(conn, "/api/v1/media/import-url", %{"url" => "https://not-enabled.example/video.mp4"})

    assert json_response(response, 403)["error"]["code"] == "source_host_not_allowed"

    assert json_response(get(build_conn(), "/api/v1/media/import-url"), 401)["error"]["code"] ==
             "unauthorized"
  end
end
