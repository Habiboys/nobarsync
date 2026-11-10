defmodule NobarSyncWeb.MediaController do
  use NobarSyncWeb, :controller

  alias NobarSync.Media

  def index(conn, params) do
    page = Media.list(conn.assigns.current_user, params)

    json(conn, %{
      items: Enum.map(page.items, &asset_json/1),
      page: page.page,
      per_page: page.per_page,
      total: page.total
    })
  end

  def show(conn, %{"id" => id}) do
    asset = Media.get_asset!(id)

    if can_read?(conn, asset),
      do: json(conn, %{media: asset_json(asset)}),
      else: {:error, :forbidden}
  end

  def processing(conn, %{"id" => id}) do
    asset = Media.get_asset!(id)

    if can_read?(conn, asset) do
      json(conn, %{
        id: asset.id,
        status: asset.status,
        progress: asset.progress,
        error: asset.error
      })
    else
      {:error, :forbidden}
    end
  end

  def update(conn, %{"id" => id} = params) do
    asset = Media.get_asset!(id)

    if owns?(conn, asset) do
      result =
        case params["share"] do
          action when action in ["request", "cancel", "withdraw"] ->
            Media.set_share(asset, action)

          nil ->
            Media.update_asset(asset, params)

          _ ->
            {:error, {:invalid, "Permintaan publikasi tidak dikenali."}}
        end

      with {:ok, asset} <- result do
        json(conn, %{media: asset_json(asset)})
      end
    else
      {:error, :forbidden}
    end
  end

  def delete(conn, %{"id" => id}) do
    asset = Media.get_asset!(id)

    if owns?(conn, asset) do
      case Media.delete_asset(asset) do
        {:ok, _} -> json(conn, %{ok: true})
        other -> other
      end
    else
      {:error, :forbidden}
    end
  end

  def add_subtitle(conn, %{"id" => id} = params) do
    asset = Media.get_asset!(id)

    if owner?(conn, asset) do
      with {:ok, subtitle} <- Media.upload_subtitle(asset, params) do
        json(conn, %{
          subtitle: %{
            language: subtitle.language,
            label: subtitle.label,
            vtt_key: subtitle.vtt_key
          }
        })
      end
    else
      {:error, :forbidden}
    end
  end

  def youtube(conn, params) do
    with {:ok, asset} <- Media.create_youtube(conn.assigns.current_user, params) do
      json(conn, %{media: asset_json(asset)})
    end
  end

  def import_url(conn, params) do
    with {:ok, asset} <- Media.create_url_import(conn.assigns.current_user, params) do
      json(conn, %{media: asset_json(asset)})
    end
  end

  def drive(conn, params) do
    NobarSync.Media.GoogleDriveProvider.import(conn.assigns.current_user, params)
  end

  def asset_json(asset) do
    %{
      id: asset.id,
      title: asset.title,
      description: asset.description,
      status: asset.status,
      source_type: asset.source_type,
      provider: asset.provider,
      youtube_id: asset.youtube_id,
      duration_ms: asset.duration_ms,
      width: asset.width,
      height: asset.height,
      poster_key: asset.poster_key,
      master_playlist_key: asset.master_playlist_key,
      progress: asset.progress,
      error: asset.error,
      visibility: asset.visibility,
      share_request: asset.share_request,
      share_note: asset.share_note,
      reviewed_at: asset.reviewed_at,
      owner_id: asset.owner_id,
      variants:
        Enum.map(
          loaded(asset.variants),
          &%{label: &1.label, bandwidth: &1.bandwidth, height: &1.height}
        ),
      subtitles:
        Enum.map(
          loaded(asset.subtitles),
          &%{language: &1.language, label: &1.label, vtt_key: &1.vtt_key}
        )
    }
  end

  defp can_read?(conn, asset) do
    user = conn.assigns.current_user
    user.role == "admin" or asset.owner_id == user.id or asset.visibility == "library"
  end

  defp owner?(conn, asset) do
    user = conn.assigns.current_user
    user.role == "admin" or asset.owner_id == user.id
  end

  # Admin changes to other people's films go through /admin/media, which requires a reason and audits.
  defp owns?(conn, asset), do: asset.owner_id == conn.assigns.current_user.id

  defp loaded(%Ecto.Association.NotLoaded{}), do: []
  defp loaded(list) when is_list(list), do: list
  defp loaded(_), do: []
end
