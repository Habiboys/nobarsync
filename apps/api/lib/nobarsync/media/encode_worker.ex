defmodule NobarSync.Media.EncodeWorker do
  use Oban.Worker,
    queue: :encode,
    max_attempts: 5,
    unique: [period: 300, fields: [:args, :worker]]

  alias NobarSync.Media
  alias NobarSync.Media.{HlsEncoder, Storage}
  alias NobarSync.Repo

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}), do: trunc(:math.pow(2, attempt) * 5)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"media_id" => media_id}}) do
    asset = Media.get_asset!(media_id)

    if asset.status == "cancelled" or (asset.status == "ready" and asset.master_playlist_key) do
      :ok
    else
      scratch =
        Path.join(
          System.tmp_dir!(),
          "nobarsync-#{asset.id}-#{System.unique_integer([:positive])}"
        )

      File.mkdir_p!(scratch)

      try do
        run(asset, scratch)
      rescue
        error ->
          Media.fail(asset, Exception.message(error))
          {:error, Exception.message(error)}
      after
        File.rm_rf(scratch)
      end
    end
  end

  defp run(asset, scratch) do
    with :ok <- ensure_active(asset),
         {:ok, asset} <- Media.mark(asset, "probing", 5),
         {:ok, source} <- fetch_source(asset, scratch),
         {:ok, meta} <- HlsEncoder.probe(source),
         :ok <- ensure_video(meta),
         {:ok, asset} <- Media.apply_probe(asset, meta),
         {:ok, asset} <- Media.mark(asset, "processing", 20),
         :ok <- ensure_active(asset),
         {:ok, ladders} <-
           HlsEncoder.encode(source, Path.join(scratch, "hls"), meta, fn ratio ->
             Media.mark(asset, "processing", 20 + ratio * 54)
           end),
         :ok <- ensure_active(asset),
         {:ok, asset} <- Media.mark(asset, "uploading", 75),
         :ok <- upload_outputs(asset, scratch, ladders, source, meta) do
      {:ok, _} = Media.mark(Repo.reload!(asset), "ready", 100)
      :ok
    else
      {:cancel, _} ->
        :ok

      {:error, reason} ->
        Media.fail(asset, inspect(reason))
        {:error, reason}
    end
  end

  defp fetch_source(asset, scratch) do
    dest = Path.join(scratch, "source.bin")

    cond do
      is_binary(asset.source_key) ->
        case Storage.download(asset.source_key, dest) do
          {:ok, :done} -> {:ok, dest}
          {:ok, _} -> {:ok, dest}
          other -> other
        end

      is_binary(asset.source_url) ->
        NobarSync.Media.UrlImport.download(asset.source_url, dest)

      true ->
        {:error, :missing_source}
    end
  end

  defp upload_outputs(asset, scratch, ladders, source, meta) do
    prefix = "videos/#{asset.id}"
    Storage.delete_prefix(prefix <> "/hls/")
    Storage.delete_prefix(prefix <> "/subtitles/")
    Storage.delete_prefix(prefix <> "/thumbnails/")
    hls_dir = Path.join(scratch, "hls")
    poster = Path.join(scratch, "poster.webp")
    HlsEncoder.poster(source, poster)
    previews = HlsEncoder.previews(source, Path.join(scratch, "previews"))
    subs = HlsEncoder.subtitles(source, Path.join(scratch, "subs"))

    :ok = upload_tree(hls_dir, prefix <> "/hls")

    if File.exists?(poster),
      do: put!(prefix <> "/thumbnails/poster.webp", File.read!(poster), "image/webp")

    Enum.each(previews, fn path ->
      put!(prefix <> "/thumbnails/" <> Path.basename(path), File.read!(path), "image/webp")
    end)

    Enum.each(subs, fn sub ->
      key = prefix <> "/subtitles/" <> Path.basename(sub.path)
      put!(key, File.read!(sub.path), "text/vtt")
      Media.insert_subtitle(asset, %{language: sub.language, label: sub.label, vtt_key: key})
    end)

    metadata = Jason.encode!(%{id: asset.id, ladders: ladders, duration_ms: meta.duration_ms})
    put!(prefix <> "/metadata.json", metadata, "application/json")

    :ok = Media.replace_variants(asset, prefix, ladders, meta)

    {:ok, _} =
      Media.put_keys(asset, %{
        poster_key: prefix <> "/thumbnails/poster.webp",
        master_playlist_key: prefix <> "/hls/master.m3u8"
      })

    :ok
  end

  defp upload_tree(dir, prefix) do
    Path.wildcard(Path.join(dir, "**/*"))
    |> Enum.filter(&File.regular?/1)
    |> Enum.each(fn path ->
      relative = Path.relative_to(path, dir) |> String.replace("\\", "/")
      put!(prefix <> "/" <> relative, File.read!(path), mime(path))
    end)

    :ok
  end

  defp put!(key, body, type) do
    case Storage.put(key, body, type) do
      {:ok, _} -> :ok
      other -> raise "Object upload failed for #{key}: #{inspect(other)}"
    end
  end

  defp mime(path) do
    case Path.extname(path) do
      ".m3u8" -> "application/vnd.apple.mpegurl"
      ".m4s" -> "video/mp4"
      ".mp4" -> "video/mp4"
      ".vtt" -> "text/vtt"
      ".webp" -> "image/webp"
      ".json" -> "application/json"
      _ -> "application/octet-stream"
    end
  end

  defp ensure_video(%{width: width}) when is_integer(width) and width > 0, do: :ok
  defp ensure_video(_), do: {:error, :not_a_video}

  defp ensure_active(asset) do
    case Repo.reload(asset) do
      %{status: "cancelled"} -> {:cancel, :cancelled}
      nil -> {:cancel, :deleted}
      _ -> :ok
    end
  end
end
