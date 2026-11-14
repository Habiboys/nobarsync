defmodule NobarSync.Messaging do
  @moduledoc false

  import Ecto.Query
  alias NobarSync.Messaging.{Message, MessageReaction, Reaction}
  alias NobarSync.Repo

  @emojis ~w(👍 ❤️ 😂 😮 😢 🔥 👏 🎉)

  def can_chat?(room, member) do
    active_member?(member) and
      case room.chat_permission do
        "off" -> false
        "host_mod" -> member.role in ["host", "moderator"]
        _ -> true
      end
  end

  def active_member?(member) do
    not is_nil(member) and is_nil(member.left_at) and not member.banned
  end

  def send_message(room, member, body, attrs \\ %{}) do
    clean = sanitize(body)
    reply_to_id = attrs[:reply_to_id] || attrs["reply_to_id"]

    cond do
      not can_chat?(room, member) ->
        {:error, :forbidden}

      clean == "" ->
        {:error, :invalid}

      true ->
        with {:ok, resolved_reply_id} <- resolve_reply_target(room.id, reply_to_id) do
          now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

          %Message{}
          |> Ecto.Changeset.change(%{
            room_id: room.id,
            member_id: member.id,
            display_name: member.display_name,
            body: clean,
            reply_to_id: resolved_reply_id,
            inserted_at: now
          })
          |> Repo.insert()
          |> case do
            {:ok, message} -> {:ok, preload_message(message)}
            error -> error
          end
        end
    end
  end

  def edit_message(room, member, message_id, body) do
    clean = sanitize(body)

    cond do
      not can_chat?(room, member) ->
        {:error, :forbidden}

      clean == "" ->
        {:error, :invalid}

      true ->
        with {:ok, uuid} <- cast_uuid(message_id),
             %Message{} = message <- find_active_message(room.id, uuid),
             true <- message.member_id == member.id do
          if clean == message.body do
            {:ok, preload_message(message)}
          else
            now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

            message
            |> Ecto.Changeset.change(%{body: clean, edited_at: now})
            |> Repo.update()
            |> case do
              {:ok, updated} -> {:ok, preload_message(updated)}
              error -> error
            end
          end
        else
          nil -> {:error, :not_found}
          false -> {:error, :forbidden}
          {:error, _} = err -> err
        end
    end
  end

  def delete_message(room, member, message_id) do
    if active_member?(member) do
      with {:ok, uuid} <- cast_uuid(message_id),
           %Message{} = message <- find_active_message(room.id, uuid) |> preload_member(),
           true <- can_delete_message?(member, message) do
        now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

        Repo.transaction(fn ->
          {:ok, deleted} =
            message
            |> Ecto.Changeset.change(%{
              deleted_at: now,
              body: "",
              pinned_at: nil,
              pinned_by_member_id: nil
            })
            |> Repo.update()

          Repo.delete_all(from r in MessageReaction, where: r.message_id == ^message.id)
          deleted
        end)
      else
        nil -> {:error, :not_found}
        false -> {:error, :forbidden}
        {:error, _} = err -> err
      end
    else
      {:error, :forbidden}
    end
  end

  def toggle_message_reaction(room, member, message_id, emoji) do
    cond do
      not active_member?(member) ->
        {:error, :forbidden}

      emoji not in @emojis ->
        {:error, :invalid}

      true ->
        with {:ok, uuid} <- cast_uuid(message_id),
             %Message{} = message <- find_active_message(room.id, uuid) do
          existing =
            Repo.get_by(MessageReaction,
              message_id: message.id,
              member_id: member.id,
              emoji: emoji
            )

          if existing do
            Repo.delete(existing)
          else
            now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

            %MessageReaction{}
            |> Ecto.Changeset.change(%{
              room_id: room.id,
              message_id: message.id,
              member_id: member.id,
              emoji: emoji,
              inserted_at: now
            })
            |> Repo.insert(
              on_conflict: :nothing,
              conflict_target: [:message_id, :member_id, :emoji]
            )
          end

          reactions =
            MessageReaction
            |> where([r], r.message_id == ^message.id)
            |> Repo.all()
            |> serialize_reactions()

          {:ok, %{message_id: message.id, reactions: reactions}}
        else
          nil -> {:error, :not_found}
          {:error, _} = err -> err
        end
    end
  end

  def pin_message(room, member, message_id, pinned \\ true) do
    if active_member?(member) and member.role in ["host", "moderator"] do
      with {:ok, uuid} <- cast_uuid(message_id),
           %Message{} = message <- find_active_message(room.id, uuid) do
        now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

        Repo.transaction(fn ->
          if pinned do
            Repo.update_all(
              from(m in Message, where: m.room_id == ^room.id and not is_nil(m.pinned_at)),
              set: [pinned_at: nil, pinned_by_member_id: nil]
            )

            {:ok, updated} =
              message
              |> Ecto.Changeset.change(%{pinned_at: now, pinned_by_member_id: member.id})
              |> Repo.update()

            preload_message(updated)
          else
            {:ok, _updated} =
              message
              |> Ecto.Changeset.change(%{pinned_at: nil, pinned_by_member_id: nil})
              |> Repo.update()

            nil
          end
        end)
      else
        nil -> {:error, :not_found}
        {:error, _} = err -> err
      end
    else
      {:error, :forbidden}
    end
  end

  def get_pinned_message(room_id) do
    Message
    |> where([m], m.room_id == ^room_id and is_nil(m.deleted_at) and not is_nil(m.pinned_at))
    |> order_by([m], desc: m.pinned_at)
    |> limit(1)
    |> preload([:member, :reply_to, :message_reactions])
    |> Repo.one()
  end

  def list_messages(room_id, before \\ nil) do
    {messages, _has_more} = list_messages_page(room_id, before)
    messages
  end

  def list_messages_page(room_id, before \\ nil) do
    query =
      Message
      |> where([m], m.room_id == ^room_id and is_nil(m.deleted_at))
      |> order_by([m], desc: m.inserted_at, desc: m.id)
      |> limit(51)
      |> preload([:member, :reply_to, :message_reactions])
      |> apply_before_cursor(room_id, before)

    rows = Repo.all(query)
    has_more = length(rows) > 50
    messages = rows |> Enum.take(50) |> Enum.reverse()
    {messages, has_more}
  end

  def send_reaction(room, member, emoji) do
    if active_member?(member) and emoji in @emojis do
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

  def serialize_message(%Message{} = message) do
    %{
      v: 1,
      id: message.id,
      body: message.body,
      display_name: message.display_name,
      member_id: message.member_id,
      author_role: author_role(message),
      inserted_at: message.inserted_at,
      edited_at: message.edited_at,
      pinned_at: message.pinned_at,
      reply_to: serialize_reply(message.reply_to),
      reactions: serialized_reactions(message)
    }
  end

  def serialize_reactions(reactions) when is_list(reactions) do
    reactions
    |> Enum.group_by(& &1.emoji)
    |> Enum.map(fn {emoji, entries} ->
      earliest =
        entries
        |> Enum.map(& &1.inserted_at)
        |> Enum.min(DateTime, fn -> nil end)

      %{
        emoji: emoji,
        count: length(entries),
        member_ids: Enum.map(entries, & &1.member_id),
        earliest: earliest
      }
    end)
    |> Enum.sort_by(fn entry ->
      unix = if entry.earliest, do: DateTime.to_unix(entry.earliest, :microsecond), else: 0
      {unix, entry.emoji}
    end)
    |> Enum.map(&Map.delete(&1, :earliest))
  end

  def sanitize(body) when is_binary(body) do
    body
    |> String.replace(~r/<[^>]*>/, "")
    |> String.trim()
    |> String.slice(0, 500)
  end

  def sanitize(_), do: ""

  defp serialize_reply(%Ecto.Association.NotLoaded{}), do: nil
  defp serialize_reply(nil), do: nil

  defp serialize_reply(%Message{deleted_at: nil} = reply) do
    %{
      id: reply.id,
      display_name: reply.display_name,
      body: reply.body,
      deleted: false
    }
  end

  defp serialize_reply(%Message{} = reply) do
    %{
      id: reply.id,
      display_name: nil,
      body: "",
      deleted: true
    }
  end

  defp resolve_reply_target(_room_id, nil), do: {:ok, nil}
  defp resolve_reply_target(_room_id, ""), do: {:ok, nil}

  defp resolve_reply_target(room_id, reply_to_id) do
    with {:ok, uuid} <- cast_uuid(reply_to_id),
         %Message{} = target <- find_active_message(room_id, uuid) do
      {:ok, target.id}
    else
      nil -> {:error, :not_found}
      {:error, _} = err -> err
    end
  end

  defp find_active_message(room_id, id) do
    Repo.one(
      from m in Message,
        where: m.id == ^id and m.room_id == ^room_id and is_nil(m.deleted_at)
    )
  end

  defp preload_message(nil), do: nil

  defp preload_message(message) do
    Repo.preload(message, [:member, :reply_to, :message_reactions], force: true)
  end

  defp author_role(%Message{member: %{role: role}}), do: role
  defp author_role(_), do: nil

  defp serialized_reactions(%Message{message_reactions: reactions}) when is_list(reactions) do
    serialize_reactions(reactions)
  end

  defp serialized_reactions(_), do: []

  defp preload_member(nil), do: nil
  defp preload_member(message), do: Repo.preload(message, :member)

  defp can_delete_message?(member, message) do
    author_role = message.member && message.member.role

    cond do
      message.member_id == member.id -> true
      member.role == "host" -> true
      member.role == "moderator" and author_role != "host" -> true
      true -> false
    end
  end

  defp cast_uuid(value) when is_binary(value) do
    case Ecto.UUID.cast(value) do
      {:ok, uuid} -> {:ok, uuid}
      :error -> {:error, :invalid}
    end
  end

  defp cast_uuid(_), do: {:error, :invalid}

  defp apply_before_cursor(query, _room_id, nil), do: query
  defp apply_before_cursor(query, _room_id, ""), do: query

  defp apply_before_cursor(query, room_id, before) do
    cond do
      dt = parse_before_datetime(before) ->
        where(query, [m], m.inserted_at < ^dt)

      match?({:ok, _}, Ecto.UUID.cast(before)) ->
        case Repo.one(
               from m in Message,
                 where: m.id == ^before and m.room_id == ^room_id,
                 select: {m.inserted_at, m.id}
             ) do
          {dt, id} ->
            where(query, [m], m.inserted_at < ^dt or (m.inserted_at == ^dt and m.id < ^id))

          nil ->
            query
        end

      true ->
        query
    end
  end

  defp parse_before_datetime(%DateTime{} = dt), do: dt

  defp parse_before_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _offset} -> dt
      _ -> nil
    end
  end

  defp parse_before_datetime(_), do: nil
end
