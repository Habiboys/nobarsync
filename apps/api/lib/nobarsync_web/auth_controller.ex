defmodule NobarSyncWeb.AuthController do
  use NobarSyncWeb, :controller

  alias NobarSync.Accounts
  alias NobarSync.Audit
  alias NobarSync.Media.Storage

  def register(conn, params) do
    with {:ok, user} <- Accounts.register_user(params),
         {:ok, session} <- Accounts.create_session(user, meta(conn)) do
      Audit.log("register",
        actor_id: user.id,
        resource_type: "user",
        resource_id: user.id,
        ip: ip(conn)
      )

      conn
      |> put_auth_cookies(session)
      |> json(%{user: user_json(user), csrf_token: session.csrf_token})
    end
  end

  def login(conn, %{"email" => email, "password" => password}) do
    with {:ok, user} <- Accounts.authenticate(email, password),
         {:ok, session} <- Accounts.create_session(user, meta(conn)) do
      Audit.log("login",
        actor_id: user.id,
        resource_type: "user",
        resource_id: user.id,
        ip: ip(conn)
      )

      conn
      |> put_auth_cookies(session)
      |> json(%{user: user_json(user), csrf_token: session.csrf_token})
    end
  end

  def login(_conn, _), do: {:error, :invalid}

  def logout(conn, _) do
    if session = conn.assigns.current_session, do: Accounts.revoke_session(session)
    if user = conn.assigns.current_user, do: Audit.log("logout", actor_id: user.id, ip: ip(conn))

    conn
    |> delete_resp_cookie("nobarsync_session", cookie_opts())
    |> delete_resp_cookie("nobarsync_csrf", csrf_opts())
    |> json(%{ok: true})
  end

  def me(conn, _) do
    cond do
      user = conn.assigns.current_user -> json(conn, %{user: user_json(user), guest: nil})
      guest = conn.assigns.current_guest -> json(conn, %{user: nil, guest: guest_json(guest)})
      true -> json(conn, %{user: nil, guest: nil})
    end
  end

  def guest(conn, %{"display_name" => name}) do
    with {:ok, result} <- Accounts.create_guest(name) do
      conn
      |> put_resp_cookie("nobarsync_guest", result.token, cookie_opts())
      |> json(%{guest: guest_json(result.guest)})
    end
  end

  def guest(_conn, _), do: {:error, :invalid}

  def socket_token(conn, _) do
    claims =
      cond do
        user = conn.assigns.current_user -> Accounts.socket_claims(user)
        true -> nil
      end

    if claims do
      token = Phoenix.Token.sign(NobarSyncWeb.Endpoint, "socket", claims, max_age: 120)
      json(conn, %{token: token, expires_in: 120})
    else
      {:error, :unauthorized}
    end
  end

  def change_password(conn, params) do
    user = conn.assigns.current_user

    if Accounts.valid_password?(user, params["old_password"]) do
      with {:ok, _} <-
             user
             |> NobarSync.Accounts.User.password_changeset(%{
               "password" => params["new_password"]
             })
             |> NobarSync.Repo.update() do
        json(conn, %{ok: true})
      end
    else
      {:error, {:invalid, "Kata sandi lama tidak sesuai."}}
    end
  end

  def update_me(conn, params) do
    with {:ok, user} <- Accounts.update_profile(conn.assigns.current_user, params) do
      json(conn, %{user: user_json(user)})
    end
  end

  def avatar(conn, %{"file" => %Plug.Upload{} = upload}) do
    bytes = File.read!(upload.path)

    if byte_size(bytes) > 1_000_000 or
         upload.content_type not in ~w(image/jpeg image/png image/webp) do
      {:error, :invalid}
    else
      ext =
        case upload.content_type do
          "image/png" -> "png"
          "image/webp" -> "webp"
          _ -> "jpg"
        end

      key = "avatars/#{conn.assigns.current_user.id}.#{ext}"
      Storage.put(key, bytes, upload.content_type)

      {:ok, user} =
        Accounts.update_profile(conn.assigns.current_user, %{
          "display_name" => conn.assigns.current_user.display_name,
          "avatar_key" => key
        })

      json(conn, %{user: user_json(user)})
    end
  end

  def avatar(_conn, _), do: {:error, :invalid}

  def user_json(user) do
    %{
      id: user.id,
      email: user.email,
      display_name: user.display_name,
      role: user.role,
      avatar_key: user.avatar_key
    }
  end

  def guest_json(guest), do: %{id: guest.id, display_name: guest.display_name}

  defp put_auth_cookies(conn, session) do
    conn
    |> put_resp_cookie("nobarsync_session", session.token, cookie_opts())
    |> put_resp_cookie("nobarsync_csrf", session.csrf_token, csrf_opts())
  end

  defp cookie_opts do
    [http_only: true, same_site: "Lax", secure: secure?(), path: "/", max_age: 1_209_600]
  end

  defp csrf_opts do
    [http_only: false, same_site: "Lax", secure: secure?(), path: "/", max_age: 1_209_600]
  end

  defp secure?, do: Application.get_env(:nobarsync, :force_secure_cookies, false)
  defp meta(conn), do: [user_agent: header(conn, "user-agent"), ip: ip(conn)]
  defp ip(conn), do: conn.remote_ip |> :inet.ntoa() |> to_string()
  defp header(conn, name), do: conn |> get_req_header(name) |> List.first()
end
