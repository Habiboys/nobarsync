defmodule NobarSync.Accounts do
  @moduledoc false

  import Ecto.Query
  alias NobarSync.Accounts.{GuestIdentity, Session, User}
  alias NobarSync.Repo

  @session_ttl_seconds 60 * 60 * 24 * 14

  def get_user!(id), do: Repo.get!(User, id)
  def get_user(id), do: Repo.get(User, id)

  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: String.downcase(email))
  end

  def register_user(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
  end

  def promote_admin(%User{} = user) do
    user |> Ecto.Changeset.change(role: "admin") |> Repo.update()
  end

  def update_profile(%User{} = user, attrs) do
    user |> User.profile_changeset(attrs) |> Repo.update()
  end

  def valid_password?(%User{password_hash: hash}, password) when is_binary(password) do
    Bcrypt.verify_pass(password, hash)
  end

  def valid_password?(_, _), do: Bcrypt.no_user_verify()

  def authenticate(email, password) do
    user = get_user_by_email(email || "")

    if valid_password?(user, password || "") do
      if user.status == "active", do: {:ok, user}, else: {:error, :account_suspended}
    else
      {:error, :invalid_credentials}
    end
  end

  def create_session(%User{} = user, meta) do
    Repo.transaction(fn ->
      current = Repo.one(from u in User, where: u.id == ^user.id, lock: "FOR UPDATE")
      if is_nil(current) or current.status != "active", do: Repo.rollback(:account_suspended)

      case insert_session(current, meta) do
        {:ok, result} -> result
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp insert_session(%User{} = user, meta) do
    token = random_token()
    csrf = random_token()
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    %Session{}
    |> Ecto.Changeset.change(%{
      user_id: user.id,
      token_hash: hash_token(token),
      csrf_token: csrf,
      expires_at: DateTime.add(now, @session_ttl_seconds, :second),
      user_agent: meta[:user_agent],
      ip: meta[:ip]
    })
    |> Repo.insert()
    |> case do
      {:ok, session} -> {:ok, %{session: session, token: token, csrf_token: csrf, user: user}}
      other -> other
    end
  end

  def get_session_by_token(token) when is_binary(token) do
    now = DateTime.utc_now()

    Session
    |> where([s], s.token_hash == ^hash_token(token))
    |> where([s], is_nil(s.revoked_at) and s.expires_at > ^now)
    |> join(:inner, [s], u in User, on: u.id == s.user_id and u.status == "active")
    |> preload(:user)
    |> Repo.one()
  end

  def revoke_session(%Session{} = session) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
    session |> Ecto.Changeset.change(revoked_at: now) |> Repo.update()
  end

  def create_guest(display_name) when is_binary(display_name) do
    name = String.trim(display_name)

    if String.length(name) < 2 or String.length(name) > 40 do
      {:error, :invalid}
    else
      token = random_token()
      now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

      %GuestIdentity{}
      |> Ecto.Changeset.change(%{
        display_name: name,
        token_hash: hash_token(token),
        last_seen_at: now
      })
      |> Repo.insert()
      |> case do
        {:ok, guest} -> {:ok, %{guest: guest, token: token}}
        other -> other
      end
    end
  end

  def get_guest_by_token(token) when is_binary(token) do
    Repo.get_by(GuestIdentity, token_hash: hash_token(token))
  end

  def touch_guest(%GuestIdentity{} = guest) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
    guest |> Ecto.Changeset.change(last_seen_at: now) |> Repo.update()
  end

  def list_users(opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per = Keyword.get(opts, :per_page, 20)

    User
    |> order_by([u], desc: u.inserted_at)
    |> limit(^per)
    |> offset(^((page - 1) * per))
    |> Repo.all()
  end

  def socket_claims(%User{} = user) do
    %{user_id: user.id, guest_id: nil, auth_version: user.auth_version}
  end

  def socket_claims(%GuestIdentity{} = guest) do
    %{user_id: nil, guest_id: guest.id}
  end

  defp random_token, do: :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  defp hash_token(token), do: :crypto.hash(:sha256, token)
end
