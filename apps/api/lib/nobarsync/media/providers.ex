defmodule NobarSync.Media.Provider do
  @callback playback(map()) :: {:ok, map()} | {:error, term()}
end

defmodule NobarSync.Media.R2HlsProvider do
  @behaviour NobarSync.Media.Provider

  def playback(%{master_playlist_key: key, status: "ready"}) when is_binary(key) do
    {:ok, %{kind: "hls", manifest_key: key}}
  end

  def playback(_), do: {:error, :media_not_ready}
end

defmodule NobarSync.Media.YouTubeEmbedProvider do
  @behaviour NobarSync.Media.Provider

  def playback(%{youtube_id: id, provider: "youtube"}) when is_binary(id) do
    {:ok, %{kind: "youtube", youtube_id: id}}
  end

  def playback(_), do: {:error, :media_not_ready}

  def extract_id(url) when is_binary(url) do
    cond do
      Regex.run(~r/(?:v=|youtu\.be\/|embed\/)([A-Za-z0-9_-]{6,})/, url) ->
        [_, id] = Regex.run(~r/(?:v=|youtu\.be\/|embed\/)([A-Za-z0-9_-]{6,})/, url)
        {:ok, id}

      Regex.match?(~r/^[A-Za-z0-9_-]{6,}$/, url) ->
        {:ok, url}

      true ->
        {:error, :invalid}
    end
  end
end

defmodule NobarSync.Media.CloudflareStreamProvider do
  @behaviour NobarSync.Media.Provider

  def playback(_asset), do: {:error, :not_implemented}
end

defmodule NobarSync.Media.GoogleDriveProvider do
  def import(_user, _attrs) do
    if blank?(System.get_env("GOOGLE_OAUTH_CLIENT_ID")) do
      {:error,
       {:disabled,
        "Impor Google Drive nonaktif. Isi GOOGLE_OAUTH_CLIENT_ID untuk menyalakan integrasi resmi."}}
    else
      {:error, {:disabled, "Impor Google Drive terisolasi dan belum diaktifkan pada build ini."}}
    end
  end

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_), do: false
end

defmodule NobarSync.Media.LocalUploadProvider do
  def source, do: "upload"
end

defmodule NobarSync.Media.ExistingR2Provider do
  def source, do: "existing"
end

defmodule NobarSync.Media.DirectURLImportProvider do
  def source, do: "url"
end
