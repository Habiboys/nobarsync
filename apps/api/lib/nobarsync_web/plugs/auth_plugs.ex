defmodule NobarSyncWeb.Plugs.RateLimit do
  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  def init(opts), do: opts

  def call(conn, opts) do
    ip = conn.remote_ip |> :inet.ntoa() |> to_string()
    bucket = opts[:bucket] || :api
    limit = opts[:limit] || 300
    window = opts[:window_ms] || 60_000

    if NobarSync.RateLimit.allow?({bucket, ip}, limit, window) do
      conn
    else
      conn
      |> put_status(429)
      |> json(%{
        error: %{code: "rate_limited", message: "Terlalu banyak permintaan", details: %{}}
      })
      |> halt()
    end
  end
end

defmodule NobarSyncWeb.Plugs.FetchSession do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    conn = fetch_cookies(conn)
    token = conn.req_cookies["nobarsync_session"]

    case NobarSync.Accounts.get_session_by_token(token || "") do
      nil ->
        assign(conn, :current_session, nil) |> assign(:current_user, nil)

      session ->
        assign(conn, :current_session, session) |> assign(:current_user, session.user)
    end
  end
end

defmodule NobarSyncWeb.Plugs.FetchGuest do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    conn = fetch_cookies(conn)

    guest =
      case conn.req_cookies["nobarsync_guest"] do
        nil -> nil
        token -> NobarSync.Accounts.get_guest_by_token(token)
      end

    assign(conn, :current_guest, if(conn.assigns[:current_user], do: nil, else: guest))
  end
end

defmodule NobarSyncWeb.Plugs.CSRF do
  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  @skip ~w(/api/v1/auth/login /api/v1/auth/register /api/v1/auth/guest)

  def init(opts), do: opts

  def call(%{method: method} = conn, _opts) when method in ["GET", "HEAD", "OPTIONS"], do: conn

  def call(conn, _opts) do
    if conn.request_path in @skip or is_nil(conn.assigns[:current_session]) do
      conn
    else
      header = conn |> get_req_header("x-nobarsync-csrf") |> List.first()
      expected = conn.assigns.current_session.csrf_token

      if is_binary(header) and byte_size(header) == byte_size(expected) and
           Plug.Crypto.secure_compare(header, expected) do
        conn
      else
        conn
        |> put_status(403)
        |> json(%{error: %{code: "csrf", message: "CSRF tidak valid", details: %{}}})
        |> halt()
      end
    end
  end
end

defmodule NobarSyncWeb.Plugs.RequireUser do
  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  def init(opts), do: opts

  def call(%{assigns: %{current_user: user}} = conn, _opts) when not is_nil(user), do: conn

  def call(conn, _opts) do
    conn
    |> put_status(401)
    |> json(%{error: %{code: "unauthorized", message: "Login diperlukan", details: %{}}})
    |> halt()
  end
end

defmodule NobarSyncWeb.Plugs.RequireAdmin do
  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  def init(opts), do: opts

  def call(%{assigns: %{current_user: %{role: "admin"}}} = conn, _opts), do: conn

  def call(conn, _opts) do
    conn
    |> put_status(403)
    |> json(%{error: %{code: "forbidden", message: "Hanya admin", details: %{}}})
    |> halt()
  end
end
