defmodule NobarSyncWeb.MediaGatewayController do
  use NobarSyncWeb, :controller

  alias NobarSync.Media.{PlaybackToken, Storage}

  def show(conn, %{"token" => token, "path" => path}) do
    key = path |> Enum.join("/")
    secret = Application.get_env(:nobarsync, :media_token_secret)

    with {:ok, claims} <- PlaybackToken.verify(token, secret),
         :ok <- PlaybackToken.authorize_path(claims, key),
         {:ok, object} <- Storage.get(key, range: range_header(conn)) do
      status = object.status_code || 200

      conn
      |> put_resp_header("content-type", mime(key))
      |> put_resp_header("accept-ranges", "bytes")
      |> put_resp_header("cache-control", "private, max-age=3600")
      |> put_resp_header("access-control-allow-origin", origin(conn))
      |> maybe_header(object.headers, "content-range")
      |> maybe_header(object.headers, "content-length")
      |> send_resp(status, object.body || "")
    else
      {:error, :expired} -> send_resp(conn, 403, "expired")
      {:error, :forbidden} -> send_resp(conn, 403, "forbidden")
      {:error, :invalid} -> send_resp(conn, 403, "forbidden")
      {:error, {:http_error, 404, _}} -> send_resp(conn, 404, "missing")
      {:error, %{status_code: 404}} -> send_resp(conn, 404, "missing")
      {:error, %{status_code: 416}} -> send_resp(conn, 416, "range")
      _ -> send_resp(conn, 404, "missing")
    end
  end

  defp range_header(conn) do
    case get_req_header(conn, "range") do
      [value | _] -> value
      _ -> nil
    end
  end

  defp maybe_header(conn, headers, name) do
    case header_value(headers || [], name) do
      nil -> conn
      value -> put_resp_header(conn, name, value)
    end
  end

  defp header_value(headers, name) do
    Enum.find_value(headers, fn
      {key, value} ->
        if String.downcase(to_string(key)) == name, do: to_string(value)

      _ ->
        nil
    end)
  end

  defp mime(key) do
    case Path.extname(key) do
      ".m3u8" -> "application/vnd.apple.mpegurl"
      ".m4s" -> "video/iso.segment"
      ".mp4" -> "video/mp4"
      ".vtt" -> "text/vtt"
      ".webp" -> "image/webp"
      ".json" -> "application/json"
      _ -> "application/octet-stream"
    end
  end

  defp origin(conn) do
    case get_req_header(conn, "origin") do
      [value | _] -> if NobarSyncWeb.CORS.allowed?(value), do: value, else: "*"
      _ -> "*"
    end
  end
end
