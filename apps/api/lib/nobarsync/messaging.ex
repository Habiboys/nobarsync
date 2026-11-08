defmodule NobarSync.Messaging do
  @moduledoc false

  import Ecto.Query
  alias NobarSync.Messaging.{Message, Reaction}
  alias NobarSync.Repo

  @emojis ~w(👍 ❤️ 😂 😮 😢 🔥 👏 🎉)

  def send_message(room, member, body) do
    clean = sanitize(body)

    cond do
      room.chat_permission == "off" ->
        {:error, :forbidden}

      room.chat_permission == "host_mod" and member.role not in ["host", "moderator"] ->
        {:error, :forbidden}

      clean == "" ->
        {:error, :invalid}

      true ->
        now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

        %Message{}
        |> Ecto.Changeset.change(%{
          room_id: room.id,
          member_id: member.id,
          display_name: member.display_name,
          body: clean,
          inserted_at: now
        })
        |> Repo.insert()
    end
  end

  def list_messages(room_id, before \\ nil) do
    query =
      Message
      |> where([m], m.room_id == ^room_id)
      |> order_by([m], desc: m.inserted_at)
      |> limit(50)

    query =
      if before do
        where(query, [m], m.inserted_at < ^before)
      else
        query
      end

    Repo.all(query) |> Enum.reverse()
  end

  def send_reaction(room, member, emoji) do
    if emoji in @emojis do
      now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

      %Reaction{}
      |> Ecto.Changeset.change(%{
        room_id: room.id,
        member_id: member.id,
        display_name: member.display_name,
        emoji: emoji,
        inserted_at: now
      })
      |> Repo.insert()
    else
      {:error, :invalid}
    end
  end

  def sanitize(body) when is_binary(body) do
    body
    |> String.replace(~r/<[^>]*>/, "")
    |> String.trim()
    |> String.slice(0, 500)
  end

  def sanitize(_), do: ""
end
