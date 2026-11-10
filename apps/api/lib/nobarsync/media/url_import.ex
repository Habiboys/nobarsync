defmodule NobarSync.Media.UrlImport do
  @moduledoc false
  @preview_bytes 65_536

  def normalize(url) when is_binary(url) do
    value = String.trim(url)

    case URI.new(value) do
      {:ok, %{scheme: "https", host: host, userinfo: nil, port: 443}}
      when is_binary(host) and host != "" ->
        if String.contains?(value, ["\"", "'", "<", ">", " ", "\n", "\r"]),
          do: {:error, :invalid_source_url},
          else: {:ok, value}

      _ ->
        {:error, :invalid_source_url}
    end
  end

  def normalize(_), do: {:error, :invalid_source_url}

  def allowed?(url) do
    with {:ok, clean} <- normalize(url),
         uri = URI.parse(clean),
         true <- host_allowed?(uri.host),
         :ok <- public_host?(uri.host) do
      :ok
    else
      false -> {:error, :source_host_not_allowed}
      {:error, _} = error -> error
      _ -> {:error, :forbidden_source}
    end
  end

  def resolve(url), do: resolve(url, 0)
  defp resolve(_url, depth) when depth > 2, do: {:error, :unsupported_player_page}

  defp resolve(url, depth) do
    with {:ok, clean} <- normalize(url),
         {:ok, final, headers, sample} <- preview(clean, 0) do
      cond do
        html?(headers, sample) ->
          with {:ok, source} <- html_source(sample, final), do: resolve(source, depth + 1)

        video?(headers, sample) ->
          with :ok <- size_allowed(headers), do: {:ok, final}

        true ->
          {:error, :unsupported_source_type}
      end
    end
  end

  def download(url, dest) do
    result = with {:ok, source} <- resolve(url), do: download_file(source, dest, 0)
    if match?({:error, _}, result), do: File.rm(dest)
    result
  end

  defp host_allowed?(host) do
    (System.get_env("IMPORT_HOST_ALLOWLIST") || "")
    |> String.split(",", trim: true)
    |> Enum.map(&(String.trim(&1) |> String.downcase()))
    |> Enum.any?(fn entry ->
      entry != "" and
        (entry == String.downcase(host) or String.ends_with?(String.downcase(host), "." <> entry))
    end)
  end

  defp public_host?(host) do
    case :inet.gethostbyname(String.to_charlist(host)) do
      {:ok, {:hostent, _, _, _, _, [_ | _] = addresses}} ->
        if Enum.all?(addresses, &public_ip?/1), do: :ok, else: {:error, :forbidden_source}

      _ ->
        {:error, :source_unreachable}
    end
  end

  defp public_ip?({a, b, _, _})
       when a in [0, 10, 127] or a >= 224 or
              (a == 172 and b in 16..31) or (a == 192 and b == 168) or
              (a == 169 and b == 254) or (a == 100 and b in 64..127),
       do: false

  defp public_ip?({_, _, _, _}), do: true
  defp public_ip?(_), do: false

  defp http, do: Application.get_env(:nobarsync, :url_import_http_client, :hackney)

  defp request(url, headers, fun) do
    options = [follow_redirect: false, connect_timeout: 8_000, recv_timeout: 30_000, pool: false]

    case http().request(:get, url, [{"accept-encoding", "identity"} | headers], "", options) do
      {:ok, status, response_headers, ref} ->
        try do
          fun.(status, response_headers, ref)
        after
          http().close(ref)
        end

      _ ->
        {:error, :source_unreachable}
    end
  end

  defp preview(_url, hops) when hops > 3, do: {:error, :too_many_redirects}

  defp preview(url, hops) do
    with :ok <- allowed?(url) do
      request(url, [{"range", "bytes=0-#{@preview_bytes - 1}"}], fn status, headers, ref ->
        cond do
          status in [301, 302, 303, 307, 308] ->
            with {:ok, next} <- redirect(url, headers), do: preview(next, hops + 1)

          status in [200, 206] ->
            with {:ok, sample} <- read_prefix(ref, @preview_bytes, []),
                 do: {:ok, url, headers, sample}

          true ->
            {:error, :source_unreachable}
        end
      end)
    end
  end

  defp read_prefix(_ref, left, parts) when left <= 0,
    do: {:ok, parts |> Enum.reverse() |> IO.iodata_to_binary()}

  defp read_prefix(ref, left, parts) do
    case http().stream_body(ref) do
      {:ok, data} ->
        chunk = binary_part(data, 0, min(byte_size(data), left))
        read_prefix(ref, left - byte_size(chunk), [chunk | parts])

      :done ->
        {:ok, parts |> Enum.reverse() |> IO.iodata_to_binary()}

      _ ->
        {:error, :source_unreachable}
    end
  end

  defp download_file(_url, _dest, hops) when hops > 3, do: {:error, :too_many_redirects}

  defp download_file(url, dest, hops) do
    with :ok <- allowed?(url) do
      request(url, [], fn status, headers, ref ->
        cond do
          status in [301, 302, 303, 307, 308] ->
            with {:ok, next} <- redirect(url, headers), do: download_file(next, dest, hops + 1)

          status == 200 ->
            with :ok <- size_allowed(headers),
                 {:ok, first} <- http().stream_body(ref),
                 true <- video?(headers, first) and not html?(headers, first),
                 {:ok, file} <- File.open(dest, [:write, :binary]) do
              try do
                with :ok <- write_chunk(file, first, 0),
                     :ok <-
                       stream_file(
                         ref,
                         file,
                         byte_size(first),
                         System.monotonic_time(:millisecond)
                       ),
                     do: {:ok, dest}
              after
                File.close(file)
              end
            else
              false -> {:error, :unsupported_source_type}
              {:error, _} = error -> error
              _ -> {:error, :source_unreachable}
            end

          true ->
            {:error, :source_unreachable}
        end
      end)
    end
  end

  defp stream_file(ref, file, bytes, started) do
    if System.monotonic_time(:millisecond) - started > 1_800_000 do
      {:error, :source_unreachable}
    else
      case http().stream_body(ref) do
        {:ok, chunk} ->
          with :ok <- write_chunk(file, chunk, bytes),
               do: stream_file(ref, file, bytes + byte_size(chunk), started)

        :done ->
          :ok

        _ ->
          {:error, :source_unreachable}
      end
    end
  end

  defp write_chunk(file, chunk, bytes) do
    if bytes + byte_size(chunk) > max_bytes(),
      do: {:error, :source_too_large},
      else: IO.binwrite(file, chunk)
  end

  defp max_bytes do
    case Integer.parse(System.get_env("IMPORT_MAX_BYTES") || "2147483648") do
      {size, ""} when size > 0 -> size
      _ -> 2_147_483_648
    end
  end

  defp size_allowed(headers) do
    value =
      case Regex.run(~r{/([0-9]+)$}, header(headers, "content-range") || "") do
        [_, total] -> total
        _ -> header(headers, "content-length") || "0"
      end

    case Integer.parse(value) do
      {size, ""} when size > 0 ->
        if size > max_bytes(), do: {:error, :source_too_large}, else: :ok

      _ ->
        :ok
    end
  end

  defp html?(headers, sample),
    do:
      String.contains?(content_type(headers), ["text/html", "application/xhtml"]) or
        Regex.match?(~r/^\s*(?:<!doctype\s+html|<html)/i, sample)

  defp video?(headers, sample) do
    type = content_type(headers)

    not String.contains?(type, ["mpegurl", "dash+xml"]) and
      not String.starts_with?(sample, "#EXTM3U") and
      (String.starts_with?(type, "video/") or
         match?(<<_::binary-size(4), "ftyp", _::binary>>, sample) or
         match?(<<0x1A, 0x45, 0xDF, 0xA3, _::binary>>, sample) or
         match?(<<"RIFF", _::binary-size(4), "AVI ", _::binary>>, sample))
  end

  defp content_type(headers), do: String.downcase(header(headers, "content-type") || "")

  defp html_source(html, page) do
    # Read static HTML5 video sources only; never run scripts or follow arbitrary iframes.
    clean = Regex.replace(~r/<!--.*?-->|<script\b[^>]*>.*?<\/script\s*>/is, html, "")
    video = Regex.run(~r/<video\b[^>]*>(?:.*?<\/video\s*>)?/is, clean)

    case video do
      [markup] ->
        tags = Regex.scan(~r/<(?:video|source)\b[^>]*>/i, markup) |> List.flatten()

        source =
          Enum.find_value(tags, fn tag ->
            case Regex.run(~r/\s+src\s*=\s*["']([^"']+)["']/i, tag) do
              [_, value] -> String.replace(value, "&amp;", "&")
              _ -> nil
            end
          end)

        if source,
          do: merge_url(page, source),
          else: {:error, :unsupported_player_page}

      _ ->
        {:error, :unsupported_player_page}
    end
  end

  defp redirect(url, headers) do
    case header(headers, "location") do
      value when is_binary(value) and value != "" -> merge_url(url, value)
      _ -> {:error, :source_unreachable}
    end
  end

  defp merge_url(base, value) do
    case URI.new(value) do
      {:ok, uri} -> normalize(URI.merge(base, uri) |> to_string())
      _ -> {:error, :invalid_source_url}
    end
  rescue
    ArgumentError -> {:error, :invalid_source_url}
  end

  defp header(headers, name),
    do:
      Enum.find_value(headers, fn {key, value} ->
        if String.downcase(to_string(key)) == name, do: to_string(value)
      end)
end
