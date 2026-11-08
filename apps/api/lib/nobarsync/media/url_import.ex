defmodule NobarSync.Media.UrlImport do
  @moduledoc false

  def allowed?(url) do
    with {:ok, uri} <- parse(url),
         true <- uri.scheme == "https",
         true <- host_allowed?(uri.host),
         :ok <- public_host?(uri.host) do
      :ok
    else
      _ -> {:error, :forbidden_source}
    end
  end

  def download(url, dest) do
    with :ok <- allowed?(url),
         {:ok, final} <- follow(url, 0),
         :ok <- write_limited(final, dest) do
      {:ok, dest}
    end
  end

  defp parse(url) do
    uri = URI.parse(url)
    if is_binary(uri.host), do: {:ok, uri}, else: :error
  end

  defp host_allowed?(host) do
    allow = System.get_env("IMPORT_HOST_ALLOWLIST") || ""

    allow
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.any?(fn entry -> entry == host or String.ends_with?(host, "." <> entry) end)
  end

  defp public_host?(host) do
    case :inet.gethostbyname(String.to_charlist(host)) do
      {:ok, {:hostent, _, _, _, _, addresses}} ->
        if Enum.all?(addresses, &public_ip?/1), do: :ok, else: :error

      _ ->
        :error
    end
  end

  defp public_ip?({a, b, _, _})
       when a == 10 or a == 127 or (a == 172 and b >= 16 and b <= 31) or (a == 192 and b == 168) or
              (a == 169 and b == 254),
       do: false

  defp public_ip?({0, _, _, _}), do: false
  defp public_ip?({_, _, _, _}), do: true
  defp public_ip?(_), do: false

  defp follow(_url, hops) when hops > 3, do: {:error, :too_many_redirects}

  defp follow(url, hops) do
    with :ok <- allowed?(url) do
      :httpc.request(:get, {String.to_charlist(url), []}, [{:autoredirect, false}],
        body_format: :binary
      )
      |> case do
        {:ok, {{_, status, _}, headers, body}} when status in [200] ->
          {:ok, {headers, body}}

        {:ok, {{_, status, _}, headers, _}} when status in [301, 302, 303, 307, 308] ->
          location = header(headers, "location")
          follow(URI.merge(url, location) |> to_string(), hops + 1)

        _ ->
          {:error, :download_failed}
      end
    end
  end

  defp write_limited({_headers, body}, dest) do
    max = String.to_integer(System.get_env("IMPORT_MAX_BYTES") || "2147483648")

    if byte_size(body) > max do
      {:error, :too_large}
    else
      File.write!(dest, body)
      :ok
    end
  end

  defp write_limited(other, _), do: other

  defp header(headers, name) do
    Enum.find_value(headers, fn {key, value} ->
      if String.downcase(to_string(key)) == name, do: to_string(value)
    end)
  end
end
