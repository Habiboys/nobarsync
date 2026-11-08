defmodule NobarSync.Media.Storage do
  @moduledoc false

  def bucket, do: System.get_env("S3_BUCKET") || "nobarsync"

  def put(key, body, content_type) do
    bucket()
    |> ExAws.S3.put_object(key, body, content_type: content_type)
    |> request(:internal)
  end

  def download(key, dest) do
    bucket()
    |> ExAws.S3.download_file(key, dest, timeout: 180_000, max_concurrency: 2)
    |> request(:internal, http_opts: [recv_timeout: 180_000, timeout: 180_000])
  end

  def get(key, opts \\ []) do
    range = Keyword.get(opts, :range)

    operation =
      if is_binary(range) and range != "" do
        ExAws.S3.get_object(bucket(), key, range: range)
      else
        ExAws.S3.get_object(bucket(), key)
      end

    request(operation, :internal)
  end

  def head(key) do
    bucket()
    |> ExAws.S3.head_object(key)
    |> request(:internal)
  end

  def delete(key) do
    bucket()
    |> ExAws.S3.delete_object(key)
    |> request(:internal)
  end

  def delete_prefix(prefix) do
    with {:ok, keys} <- list(prefix) do
      keys
      |> Enum.chunk_every(200)
      |> Enum.reduce_while(:ok, fn
        [], acc ->
          {:cont, acc}

        chunk, _acc ->
          case bucket() |> ExAws.S3.delete_multiple_objects(chunk) |> request(:internal) do
            {:ok, _} -> {:cont, :ok}
            other -> {:halt, other}
          end
      end)
    end
  end

  def list(prefix), do: list_page(prefix, nil, [])

  defp list_page(prefix, marker, accumulated) do
    opts = if marker, do: [prefix: prefix, marker: marker], else: [prefix: prefix]

    case bucket() |> ExAws.S3.list_objects(opts) |> request(:internal) do
      {:ok, %{body: body}} ->
        keys = keys_from(body)
        truncated = body[:is_truncated] in [true, "true"]

        next =
          case body[:next_marker] do
            value when is_binary(value) and value != "" -> value
            _ -> List.last(keys)
          end

        if (truncated and next) && next != marker do
          list_page(prefix, next, accumulated ++ keys)
        else
          {:ok, accumulated ++ keys}
        end

      other ->
        other
    end
  end

  def initiate_multipart(key, content_type) do
    bucket()
    |> ExAws.S3.initiate_multipart_upload(key, content_type: content_type)
    |> request(:internal)
    |> case do
      {:ok, response} -> {:ok, extract_upload_id(response)}
      other -> other
    end
  end

  def presign_part(key, upload_id, part_number) do
    config = Map.new(s3_config(:public))

    ExAws.S3.presigned_url(config, :put, bucket(), key,
      virtual_host: false,
      expires_in: 3600,
      query_params: %{"uploadId" => upload_id, "partNumber" => Integer.to_string(part_number)}
    )
  end

  def list_uploads(prefix \\ "") do
    bucket()
    |> ExAws.S3.list_multipart_uploads(prefix: prefix)
    |> request(:internal)
  end

  def list_parts(key, upload_id) do
    bucket()
    |> ExAws.S3.list_parts(key, upload_id)
    |> request(:internal)
  end

  def complete_multipart(key, upload_id, parts) do
    formatted =
      Enum.map(parts, fn part ->
        {part.part_number, part.etag}
      end)

    bucket()
    |> ExAws.S3.complete_multipart_upload(key, upload_id, formatted)
    |> request(:internal)
  end

  def abort_multipart(key, upload_id) do
    bucket()
    |> ExAws.S3.abort_multipart_upload(key, upload_id)
    |> request(:internal)
  end

  def request(operation, which, extra \\ []) do
    ExAws.request(operation, Keyword.merge(s3_config(which), extra))
  end

  def s3_config(which) do
    public? = which == :public

    [
      access_key_id: env("S3_ACCESS_KEY", "nobarsync"),
      secret_access_key: env("S3_SECRET_KEY", "nobarsync-secret"),
      region: env("S3_REGION", "us-east-1"),
      scheme: env(if(public?, do: "S3_PUBLIC_SCHEME", else: "S3_SCHEME"), "http://"),
      host: env(if(public?, do: "S3_PUBLIC_HOST", else: "S3_HOST"), "localhost"),
      port: String.to_integer(env(if(public?, do: "S3_PUBLIC_PORT", else: "S3_PORT"), "9000"))
    ]
  end

  defp env(name, default) do
    case System.get_env(name) do
      nil -> default
      "" -> default
      value -> value
    end
  end

  defp keys_from(%{contents: contents}) when is_list(contents), do: Enum.map(contents, &key_of/1)

  defp keys_from(%{"contents" => contents}) when is_list(contents),
    do: Enum.map(contents, &key_of/1)

  defp keys_from(_), do: []

  defp key_of(%{key: key}), do: key
  defp key_of(%{"key" => key}), do: key
  defp key_of(other), do: to_string(other[:key] || "")

  defp extract_upload_id(%{body: body}) when is_map(body) do
    body[:upload_id] || body["upload_id"] || body[:UploadId] || body["UploadId"] ||
      get_in(body, [:initiate_multipart_upload_result, :upload_id])
  end

  defp extract_upload_id(_), do: nil
end
