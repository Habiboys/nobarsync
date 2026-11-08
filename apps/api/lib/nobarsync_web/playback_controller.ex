defmodule NobarSyncWeb.PlaybackController do
  use NobarSyncWeb, :controller

  alias NobarSync.{Media, WatchRooms}

  def token(conn, params) do
    secret = Application.get_env(:nobarsync, :media_token_secret)

    cond do
      code = params["room_code"] ->
        with %{} = room <- WatchRooms.get_room_by_code(code),
             %{} <- WatchRooms.active_member(room.id, actor(conn)),
             %{} = asset <- Media.get_asset(room.media_asset_id),
             asset = NobarSync.Repo.preload(asset, [:variants, :subtitles]),
             {:ok, issued} <- Media.issue_token(asset, room.id, secret),
             {:ok, playback} <- Media.playback(asset) do
          json(conn, Map.merge(issued, playback_meta(asset, playback)))
        else
          nil -> {:error, :not_found}
          other -> other
        end

      id = params["media_id"] ->
        asset = Media.get_asset!(id)
        user = conn.assigns.current_user

        if user &&
             (user.id == asset.owner_id or user.role == "admin" or asset.visibility == "library") do
          with {:ok, issued} <- Media.issue_token(asset, nil, secret),
               {:ok, playback} <- Media.playback(asset) do
            json(conn, Map.merge(issued, playback_meta(asset, playback)))
          end
        else
          {:error, :forbidden}
        end

      true ->
        {:error, :invalid}
    end
  end

  defp actor(conn), do: %{user: conn.assigns.current_user, guest: conn.assigns.current_guest}

  defp playback_meta(asset, playback) do
    %{
      playback: playback,
      media_id: asset.id,
      title: asset.title,
      poster_key: asset.poster_key,
      subtitles:
        Enum.map(
          asset.subtitles || [],
          &%{language: &1.language, label: &1.label, vtt_key: &1.vtt_key}
        ),
      variants:
        Enum.map(
          asset.variants || [],
          &%{label: &1.label, height: &1.height, bandwidth: &1.bandwidth}
        )
    }
  end
end
