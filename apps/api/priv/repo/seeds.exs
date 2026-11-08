alias NobarSync.Accounts

admin_email = System.get_env("SEED_ADMIN_EMAIL") || "admin@nobarsync.local"
admin_password = System.get_env("SEED_ADMIN_PASSWORD") || "nobarsync-dev"
host_email = System.get_env("SEED_HOST_EMAIL") || "host@nobarsync.local"
host_password = System.get_env("SEED_HOST_PASSWORD") || "nobarsync-dev"

unless Accounts.get_user_by_email(admin_email) do
  {:ok, _} =
    Accounts.register_user(%{
      "email" => admin_email,
      "password" => admin_password,
      "display_name" => "Admin"
    })

  user = Accounts.get_user_by_email(admin_email)
  {:ok, _} = Accounts.promote_admin(user)
end

unless Accounts.get_user_by_email(host_email) do
  {:ok, _} =
    Accounts.register_user(%{
      "email" => host_email,
      "password" => host_password,
      "display_name" => "Host"
    })
end
