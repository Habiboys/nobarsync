defmodule NobarSyncWeb.UploadController do
  use NobarSyncWeb, :controller

  alias NobarSync.Media
  alias NobarSyncWeb.MediaController

  def create(conn, params) do
    with {:ok, result} <- Media.create_upload(conn.assigns.current_user, params) do
      json(conn, %{
        media: MediaController.asset_json(result.asset),
        upload_session_id: result.session.id,
        part_size: result.part_size,
        part_count: result.part_count
      })
    end
  end

  def part(conn, %{"id" => id, "part_number" => part}) do
    number =
      case part do
        value when is_integer(value) ->
          value

        value when is_binary(value) ->
          case Integer.parse(value) do
            {number, ""} -> number
            _ -> 0
          end

        _ ->
          0
      end

    case Media.sign_part(conn.assigns.current_user, id, number) do
      {:ok, url} -> json(conn, %{url: url, part_number: number})
      other -> other
    end
  end

  def complete(conn, %{"id" => id} = params) do
    with {:ok, asset} <-
           Media.complete_upload(conn.assigns.current_user, id, params["parts"] || []) do
      json(conn, %{media: MediaController.asset_json(Media.get_asset!(asset.id))})
    end
  end

  def abort(conn, %{"id" => id}) do
    with :ok <- Media.abort_upload(conn.assigns.current_user, id) do
      json(conn, %{ok: true})
    end
  end
end
