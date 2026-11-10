alias NobarSync.Accounts.User
alias NobarSync.Repo

user = Repo.get_by!(User, email: "uji-pustaka@example.com")
user = user |> Ecto.Changeset.change(role: "user") |> Repo.update!()
IO.puts(user.role)
