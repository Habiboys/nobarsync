defmodule NobarSync.Audit do
  @moduledoc false

  alias NobarSync.Repo

  def log(action, opts \\ []) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    %NobarSync.Audit.Log{}
    |> Ecto.Changeset.change(%{
      actor_user_id: opts[:actor_id],
      action: action,
      resource_type: opts[:resource_type],
      resource_id: opts[:resource_id] && to_string(opts[:resource_id]),
      metadata: opts[:metadata] || %{},
      ip: opts[:ip],
      inserted_at: now
    })
    |> Repo.insert()
  end
end
