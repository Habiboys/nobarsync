defmodule NobarSync.Media do
  @moduledoc false

  import Ecto.Query
  alias NobarSync.Media.{Asset, PlaybackToken, Storage, Subtitle, UploadSession, Variant}
  alias NobarSync.Repo

  @part_size 8_388_608

  def get_asset!(id), do: Repo.get!(Asset, id) |> Repo.preload([:variants, :subtitles])
  def get_asset(id), do: if(id, do: Repo.get(Asset, id), else: nil)

  def list(user, params) do
    page = parse_int(params["page"], 1)
    per = min(parse_int(params["per_page"], 20), 50)
    q = "%#{params["q"] || ""}%"

    query =
      Asset
      |> where([a], a.owner_id == ^user.id or a.visibility == "library")
      |> where([a], ilike(a.title, ^q))
      |> maybe_status(params["status"])
      |> maybe_share(params["share"])
      |> order_by([a], desc: a.inserted_at)

    total = Repo.aggregate(query, :count)

    items =
      query
      |> limit(^per)
      |> offset(^((page - 1) * per))
      |> Repo.all()
      |> Repo.preload([:variants, :subtitles])

    %{items: items, page: page, per_page: per, total: total}
  end

  def create_upload(user, attrs) do
    title = attrs["title"] || attrs["filename"] || "Tanpa judul"
    content_type = attrs["content_type"] || "application/octet-stream"
    byte_size = parse_int(attrs["byte_size"], 0)
    max = String.to_integer(System.get_env("MAX_UPLOAD_BYTES") || "8589934592")

    cond do
      byte_size <= 0 or byte_size > max ->
        {:error, {:invalid, "Ukuran berkas tidak valid."}}

      content_type not in ~w(video/mp4 video/quicktime video/webm video/x-matroska application/octet-stream) ->
        {:error, {:invalid, "Jenis berkas tidak didukung. Gunakan MP4, MOV, WebM, atau MKV."}}

      true ->
        asset =
          %Asset{}
          |> Asset.changeset(%{
            owner_id: user.id,
            title: title,
            description: attrs["description"],
            status: "pending",
            source_type: "upload",
            provider: "r2_hls",
            content_type: content_type,
            byte_size: byte_size
          })
          |> put_publication(attrs)
          |> Repo.insert!()

        key = "videos/#{asset.id}/source/original.bin"

        case Storage.initiate_multipart(key, content_type) do
          {:ok, upload_id} when is_binary(upload_id) ->
            now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

            session_changeset =
              %UploadSession{}
              |> Ecto.Changeset.change(%{
                owner_id: user.id,
                media_asset_id: asset.id,
                object_key: key,
                upload_id: upload_id,
                status: "active",
                part_size: @part_size,
                bytes_expected: byte_size,
                content_type: content_type,
                expires_at: DateTime.add(now, 24 * 3600, :second)
              })

            case Repo.insert(session_changeset) do
              {:ok, session} ->
                asset = asset |> Ecto.Changeset.change(source_key: key) |> Repo.update!()

                {:ok,
                 %{
                   asset: asset,
                   session: session,
                   part_size: @part_size,
                   part_count: max(div(byte_size + @part_size - 1, @part_size), 1)
                 }}

              {:error, _reason} ->
                _ = Storage.abort_multipart(key, upload_id)
                Repo.delete(asset)
                {:error, {:invalid, "Pencatatan unggahan gagal. Berkas tidak masuk."}}
            end

          other ->
            require Logger
            Logger.error("multipart init failed: #{inspect(other)}")
            Repo.delete(asset)
            {:error, {:invalid, "Penyimpanan tidak bisa memulai unggahan. Film tidak dicatat."}}
        end
    end
  end

  def sign_part(user, session_id, part_number) do
    with %UploadSession{status: "active"} = session <- Repo.get(UploadSession, session_id),
         true <- session.owner_id == user.id,
         true <- DateTime.compare(session.expires_at, DateTime.utc_now()) == :gt,
         true <-
           is_integer(part_number) and part_number > 0 and
             part_number <= div(session.bytes_expected + session.part_size - 1, session.part_size) do
      Storage.presign_part(session.object_key, session.upload_id, part_number)
    else
      _ -> {:error, :not_found}
    end
  end

  def complete_upload(user, session_id, parts) do
    with %UploadSession{status: "active"} = session <- Repo.get(UploadSession, session_id),
         true <- session.owner_id == user.id,
         true <- DateTime.compare(session.expires_at, DateTime.utc_now()) == :gt,
         :ok <- validate_upload_parts(session, parts),
         asset when not is_nil(asset) <- Repo.get(Asset, session.media_asset_id) do
      case Storage.complete_multipart(
             session.object_key,
             session.upload_id,
             normalize_parts(parts)
           ) do
        {:ok, completed} ->
          checksum = complete_etag(completed) || checksum_from_head(session.object_key)

          result =
            with :ok <- verify_uploaded_size(session),
                 do: record_completed(session, asset, checksum)

          case result do
            {:ok, asset} ->
              {:ok, asset}

            {:error, reason} ->
              Storage.delete(session.object_key)
              {:error, reason}
          end

        other ->
          require Logger
          Logger.error("multipart complete failed: #{inspect(other)}")
          _ = Storage.abort_multipart(session.object_key, session.upload_id)
          drop_asset(asset)
          {:error, {:invalid, "Penyimpanan menolak unggahan. Film tidak dicatat."}}
      end
    else
      false -> {:error, :forbidden}
      nil -> {:error, :not_found}
      %UploadSession{} -> {:error, {:invalid, "Sesi unggahan sudah selesai atau dibatalkan."}}
      {:error, _} = error -> error
    end
  end

  defp validate_upload_parts(session, parts) when is_list(parts) do
    expected = div(session.bytes_expected + session.part_size - 1, session.part_size)

    valid =
      Enum.all?(parts, fn p ->
        is_map(p) and is_binary(p["etag"] || p[:etag]) and
          byte_size(p["etag"] || p[:etag]) in 1..200
      end)

    numbers =
      if valid, do: Enum.map(normalize_parts(parts), & &1.part_number) |> Enum.sort(), else: []

    if valid and numbers == Enum.to_list(1..expected),
      do: :ok,
      else:
        {:error, {:invalid, "Bagian unggahan belum lengkap atau duplikat. Lanjutkan unggahan."}}
  end

  defp validate_upload_parts(_, _), do: {:error, :invalid}

  defp verify_uploaded_size(session) do
    with {:ok, head} <- Storage.head(session.object_key),
         size when is_binary(size) <- header_value(head, "content-length"),
         {actual, ""} <- Integer.parse(size),
         true <- actual == session.bytes_expected do
      :ok
    else
      _ -> {:error, {:invalid, "Ukuran objek tidak sesuai dengan unggahan yang didaftarkan."}}
    end
  end

  defp record_completed(session, asset, checksum) do
    Repo.transaction(fn ->
      with {:ok, _} <- session |> Ecto.Changeset.change(status: "completed") |> Repo.update(),
           {:ok, asset} <-
             asset
             |> Ecto.Changeset.change(%{status: "queued", checksum: checksum, progress: 0.0})
             |> Repo.update(),
           {:ok, _job} <- Oban.insert(NobarSync.Media.EncodeWorker.new(%{"media_id" => asset.id})) do
        asset
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, asset} -> {:ok, asset}
      {:error, _} -> {:error, {:invalid, "Pencatatan gagal. Berkas di penyimpanan dibatalkan."}}
    end
  end

  defp drop_asset(asset) do
    Repo.delete_all(from s in UploadSession, where: s.media_asset_id == ^asset.id)
    Repo.delete(asset)
  end

  defp checksum_from_head(key) do
    case Storage.head(key) do
      {:ok, head} -> header_value(head, "ETag")
      _ -> nil
    end
  end

  defp complete_etag({:ok, %{body: body}}) when is_map(body), do: body[:etag] || body["etag"]
  defp complete_etag(%{body: body}) when is_map(body), do: body[:etag] || body["etag"]
  defp complete_etag(_), do: nil

  def finish_open_uploads do
    UploadSession
    |> where([s], s.status == "active")
    |> Repo.all()
    |> Enum.map(fn session ->
      parts =
        case Storage.list_parts(session.object_key, session.upload_id) do
          {:ok, %{body: %{parts: parts}}} when is_list(parts) ->
            Enum.map(parts, fn part ->
              %{"part_number" => part.part_number, "etag" => part.etag}
            end)

          other ->
            other
        end

      result =
        if is_list(parts) and parts != [] do
          complete_upload(%{id: session.owner_id}, session.id, parts)
        else
          {:error, parts}
        end

      {session.object_key, result}
    end)
  end

  def abort_upload(user, session_id) do
    with %UploadSession{} = session <- Repo.get(UploadSession, session_id),
         true <- session.owner_id == user.id do
      Storage.abort_multipart(session.object_key, session.upload_id)
      session |> Ecto.Changeset.change(status: "aborted") |> Repo.update!()
      if asset = Repo.get(Asset, session.media_asset_id), do: mark(asset, "cancelled", 0)
      :ok
    else
      _ -> {:error, :not_found}
    end
  end

  def create_youtube(user, attrs) do
    url = attrs["url"] || ""

    with {:ok, id} <- NobarSync.Media.YouTubeEmbedProvider.extract_id(url) do
      title =
        case attrs["title"] do
          value when is_binary(value) and value != "" -> value
          _ -> "YouTube #{id}"
        end

      %Asset{}
      |> Asset.changeset(%{
        owner_id: user.id,
        title: title,
        status: "ready",
        source_type: "youtube",
        provider: "youtube",
        youtube_id: id,
        source_url: url,
        progress: 100.0
      })
      |> put_publication(attrs)
      |> Repo.insert()
    else
      {:error, :invalid} ->
        {:error,
         {:invalid, "URL YouTube tidak dikenali. Tempel tautan youtube.com atau youtu.be."}}

      other ->
        other
    end
  end

  def update_asset(%Asset{} = asset, attrs, opts \\ []) do
    changes = %{
      title: present(attrs["title"]) || asset.title,
      description:
        if(Map.has_key?(attrs, "description"), do: attrs["description"], else: asset.description)
    }

    review =
      if opts[:admin] do
        %{
          visibility: present(attrs["visibility"]) || asset.visibility,
          share_request: present(attrs["share_request"]) || asset.share_request,
          share_note:
            if(Map.has_key?(attrs, "share_note"), do: attrs["share_note"], else: asset.share_note),
          reviewed_at:
            if(Map.has_key?(attrs, "reviewed_at"),
              do: attrs["reviewed_at"],
              else: asset.reviewed_at
            )
        }
      else
        %{}
      end

    asset
    |> Asset.changeset(Map.merge(changes, review))
    |> force_review(review)
    |> Repo.update()
  end

  def set_share(%Asset{status: "cancelled"}, _),
    do: {:error, {:invalid, "Film yang dibatalkan tidak bisa diajukan."}}

  def set_share(%Asset{visibility: "library"}, "request"),
    do: {:error, {:invalid, "Film ini sudah ada di pustaka bersama."}}

  def set_share(%Asset{share_request: "pending"} = asset, "request"), do: {:ok, asset}

  def set_share(%Asset{} = asset, "request") do
    review_change(asset, %{share_request: "pending", share_note: nil, reviewed_at: nil})
  end

  def set_share(%Asset{share_request: "pending"} = asset, "cancel") do
    review_change(asset, %{share_request: "none", share_note: nil, reviewed_at: nil})
  end

  def set_share(%Asset{visibility: "library"} = asset, "withdraw") do
    review_change(asset, %{
      visibility: "private",
      share_request: "none",
      share_note: nil,
      reviewed_at: nil
    })
  end

  def set_share(_, "cancel"),
    do: {:error, {:invalid, "Tidak ada permintaan yang bisa dibatalkan."}}

  def set_share(_, "withdraw"),
    do: {:error, {:invalid, "Film ini tidak sedang di pustaka bersama."}}

  def set_share(_, _), do: {:error, {:invalid, "Permintaan publikasi tidak dikenali."}}

  def create_url_import(user, attrs) do
    url = attrs["url"] || ""

    with :ok <- NobarSync.Media.UrlImport.allowed?(url) do
      {:ok, asset} =
        %Asset{}
        |> Asset.changeset(%{
          owner_id: user.id,
          title: attrs["title"] || "Impor URL",
          status: "queued",
          source_type: "url",
          provider: "r2_hls",
          source_url: url
        })
        |> put_publication(attrs)
        |> Repo.insert()

      {:ok, _} = Oban.insert(NobarSync.Media.EncodeWorker.new(%{"media_id" => asset.id}))
      {:ok, asset}
    end
  end

  def delete_asset(%Asset{} = asset) do
    with :ok <- abort_open_sessions(asset),
         :ok <- Storage.delete_prefix("videos/#{asset.id}/") do
      Repo.delete_all(from s in UploadSession, where: s.media_asset_id == ^asset.id)
      Repo.delete(asset)
    else
      _ ->
        {:error, {:invalid, "Berkas di bucket belum terhapus, jadi datanya tetap ada."}}
    end
  end

  def discard_incomplete do
    uploads =
      case Storage.list_uploads() do
        {:ok, %{body: %{uploads: uploads}}} when is_list(uploads) -> uploads
        _ -> []
      end

    aborted =
      Enum.map(uploads, fn upload ->
        {upload.key, Storage.abort_multipart(upload.key, upload.upload_id)}
      end)

    removed =
      Asset
      |> where([a], a.status == "pending" and a.source_type == "upload")
      |> Repo.all()
      |> Enum.map(fn asset ->
        Repo.delete_all(from s in UploadSession, where: s.media_asset_id == ^asset.id)
        Repo.delete(asset)
        asset.title
      end)

    %{aborted: aborted, removed: removed}
  end

  defp abort_open_sessions(asset) do
    UploadSession
    |> where([s], s.media_asset_id == ^asset.id and s.status == "active")
    |> Repo.all()
    |> Enum.reduce_while(:ok, fn session, :ok ->
      case Storage.abort_multipart(session.object_key, session.upload_id) do
        {:ok, _} -> {:cont, :ok}
        {:error, {:http_error, 404, _}} -> {:cont, :ok}
        other -> {:halt, other}
      end
    end)
  end

  def mark(asset, status, progress) do
    {:ok, updated} =
      asset
      |> Asset.changeset(%{status: status, progress: progress / 1})
      |> Repo.update()

    NobarSync.Media.ProgressListener.notify(%{
      "media_id" => asset.id,
      "owner_id" => asset.owner_id,
      "status" => status,
      "progress" => progress
    })

    {:ok, updated}
  end

  def fail(asset, reason) do
    asset
    |> Asset.changeset(%{status: "failed", error: String.slice(to_string(reason), 0, 500)})
    |> Repo.update()

    NobarSync.Media.ProgressListener.notify(%{
      "media_id" => asset.id,
      "owner_id" => asset.owner_id,
      "status" => "failed",
      "progress" => asset.progress
    })
  end

  def apply_probe(asset, meta) do
    asset
    |> Ecto.Changeset.change(%{
      duration_ms: meta.duration_ms,
      width: meta.width,
      height: meta.height
    })
    |> Repo.update()
  end

  def put_keys(asset, attrs), do: asset |> Ecto.Changeset.change(attrs) |> Repo.update()

  def insert_subtitle(asset, attrs) do
    %Subtitle{}
    |> Ecto.Changeset.change(Map.put(attrs, :media_asset_id, asset.id))
    |> Repo.insert(
      on_conflict: {:replace_all_except, [:id, :inserted_at]},
      conflict_target: [:media_asset_id, :language]
    )
  end

  def upload_subtitle(asset, params) do
    lang =
      (params["language"] || "id")
      |> to_string()
      |> String.trim()
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9_-]/, "")

    label = present(params["label"]) || String.upcase(lang)
    body = to_string(params["content"] || "")

    cond do
      lang == "" ->
        {:error, {:invalid, "Kode bahasa subtitle wajib diisi."}}

      byte_size(body) == 0 or not String.contains?(body, "-->") ->
        {:error, {:invalid, "Berkas subtitle harus berformat WebVTT (.vtt)."}}

      byte_size(body) > 2_000_000 ->
        {:error, {:invalid, "Ukuran subtitle terlalu besar."}}

      true ->
        normalized =
          if String.starts_with?(String.trim_leading(body), "WEBVTT"),
            do: body,
            else: "WEBVTT\n\n" <> body

        key = "videos/#{asset.id}/subtitles/#{lang}.vtt"

        with {:ok, _} <- Storage.put(key, normalized, "text/vtt") do
          insert_subtitle(asset, %{language: lang, label: label, vtt_key: key})
        end
    end
  end

  def replace_variants(asset, prefix, ladders, _meta) do
    Repo.delete_all(from v in Variant, where: v.media_asset_id == ^asset.id)

    Enum.each(ladders, fn ladder ->
      bandwidth =
        ladder.bitrate
        |> String.trim_trailing("k")
        |> Integer.parse()
        |> case do
          {n, _} -> n * 1000
          _ -> 1_000_000
        end

      %Variant{}
      |> Ecto.Changeset.change(%{
        media_asset_id: asset.id,
        label: ladder.name,
        playlist_key: "#{prefix}/hls/#{ladder.name}.m3u8",
        bandwidth: bandwidth,
        height: if(ladder.height > 0, do: ladder.height),
        codecs: "avc1.640028,mp4a.40.2"
      })
      |> Repo.insert!()
    end)

    :ok
  end

  def issue_token(asset, room_id, secret) do
    prefix = "videos/#{asset.id}/"
    exp = System.system_time(:second) + 2 * 60 * 60

    token =
      PlaybackToken.sign(
        %{exp: exp, media_id: asset.id, prefix: prefix, room_id: room_id, scope: "playback"},
        secret
      )

    {:ok, %{token: token, prefix: prefix, expires_at: exp}}
  end

  def playback(asset) do
    case asset.provider do
      "youtube" -> NobarSync.Media.YouTubeEmbedProvider.playback(asset)
      "cloudflare_stream" -> NobarSync.Media.CloudflareStreamProvider.playback(asset)
      _ -> NobarSync.Media.R2HlsProvider.playback(asset)
    end
  end

  defp present(value) when is_binary(value) and value != "", do: value
  defp present(_), do: nil

  defp maybe_status(query, status) when status in [nil, ""], do: query
  defp maybe_status(query, status), do: where(query, [a], a.status == ^status)

  defp maybe_share(query, share) when share in ["none", "pending", "approved", "rejected"],
    do: where(query, [a], a.share_request == ^share)

  defp maybe_share(query, _), do: query

  defp put_publication(changeset, attrs) do
    fields =
      case attrs["audience"] do
        audience when audience in ["library", "public"] ->
          %{visibility: "private", share_request: "pending"}

        _ ->
          %{visibility: "private", share_request: "none"}
      end

    Ecto.Changeset.change(changeset, fields)
  end

  defp review_change(asset, fields) do
    asset
    |> Ecto.Changeset.change(fields)
    |> Ecto.Changeset.validate_inclusion(:share_request, ~w(none pending approved rejected))
    |> Ecto.Changeset.validate_inclusion(:visibility, ~w(private library))
    |> Repo.update()
  end

  defp force_review(changeset, review) when map_size(review) == 0, do: changeset

  defp force_review(changeset, review) do
    Enum.reduce([:visibility, :share_request, :share_note, :reviewed_at], changeset, fn key,
                                                                                        next ->
      Ecto.Changeset.force_change(next, key, Map.get(review, key))
    end)
  end

  defp parse_int(value, _default) when is_integer(value), do: value

  defp parse_int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {n, _} -> n
      :error -> default
    end
  end

  defp parse_int(_, default), do: default

  defp normalize_parts(parts) do
    Enum.map(parts, fn part ->
      %{
        part_number: parse_int(part["part_number"] || part[:part_number], 0),
        etag: part["etag"] || part[:etag]
      }
    end)
  end

  defp header_value(%{headers: headers}, name) do
    Enum.find_value(headers, fn
      {key, value} ->
        if String.downcase(to_string(key)) == String.downcase(name), do: to_string(value)

      _ ->
        nil
    end)
  end

  defp header_value(_, _), do: nil
end
