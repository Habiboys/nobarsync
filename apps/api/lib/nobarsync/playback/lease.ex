defmodule NobarSync.Playback.Lease do
  @moduledoc false

  alias NobarSync.Repo

  def acquire(room_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
    expires = DateTime.add(now, 30, :second)
    node_id = node_id()

    sql = """
    INSERT INTO room_leases (room_id, node_id, fencing_token, expires_at, inserted_at, updated_at)
    VALUES ($1::uuid, $2, 1, $3, $4, $4)
    ON CONFLICT (room_id) DO UPDATE
      SET node_id = EXCLUDED.node_id,
          fencing_token = room_leases.fencing_token + 1,
          expires_at = EXCLUDED.expires_at,
          updated_at = EXCLUDED.updated_at
    WHERE room_leases.expires_at < EXCLUDED.updated_at
       OR room_leases.node_id = EXCLUDED.node_id
    RETURNING fencing_token
    """

    case Repo.query(sql, [Ecto.UUID.dump!(room_id), node_id, expires, now]) do
      {:ok, %{num_rows: 1, rows: [[token]]}} -> {:ok, token}
      {:ok, %{num_rows: 0}} -> {:error, :lease_held}
      {:error, reason} -> {:error, reason}
    end
  end

  def renew(room_id, token) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
    expires = DateTime.add(now, 30, :second)

    Repo.query(
      """
      UPDATE room_leases
      SET expires_at = $3, updated_at = $4
      WHERE room_id = $1::uuid AND fencing_token = $2 AND node_id = $5
      """,
      [Ecto.UUID.dump!(room_id), token, expires, now, node_id()]
    )
  end

  def release(room_id, token) do
    Repo.query(
      "DELETE FROM room_leases WHERE room_id = $1::uuid AND fencing_token = $2 AND node_id = $3",
      [Ecto.UUID.dump!(room_id), token, node_id()]
    )
  end

  defp node_id, do: Atom.to_string(node())
end
