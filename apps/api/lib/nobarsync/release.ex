defmodule NobarSync.Release do
  @moduledoc false

  @app :nobarsync

  def migrate do
    load_app()

    for repo <- Application.fetch_env!(@app, :ecto_repos) do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, fn repo ->
          Ecto.Migrator.run(repo, :up, all: true)
          bootstrap_admin()
        end)
    end
  end

  defp bootstrap_admin do
    email = System.get_env("BOOTSTRAP_ADMIN_EMAIL", "") |> String.trim()
    password = System.get_env("BOOTSTRAP_ADMIN_PASSWORD", "")

    if email != "" do
      case NobarSync.Accounts.get_user_by_email(email) do
        %{role: "admin"} ->
          :ok

        nil ->
          if String.length(password) < 12,
            do: raise("BOOTSTRAP_ADMIN_PASSWORD must contain at least 12 characters")

          {:ok, _} = Application.ensure_all_started(:bcrypt_elixir)

          {:ok, admin} =
            NobarSync.Accounts.register_user(%{
              "email" => email,
              "display_name" => "Admin Manonton",
              "password" => password
            })

          {:ok, _} = NobarSync.Accounts.promote_admin(admin)

        _ ->
          raise("Bootstrap email belongs to a non-admin account; choose another email")
      end
    end
  end

  defp load_app do
    Application.load(@app)
  end
end
