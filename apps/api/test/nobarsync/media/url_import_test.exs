defmodule NobarSync.Media.UrlImportTest.Http do
  def request(:get, url, _headers, "", _options) do
    [response | rest] = Process.get(:import_responses)
    Process.put(:import_responses, rest)
    send(self(), {:requested, url})
    {status, headers, chunks} = response
    ref = make_ref()
    Process.put(ref, chunks)
    {:ok, status, headers, ref}
  end

  def stream_body(ref) do
    case Process.get(ref, []) do
      [] ->
        :done

      [chunk | rest] ->
        Process.put(ref, rest)
        {:ok, chunk}
    end
  end

  def close(ref), do: Process.delete(ref)
end

defmodule NobarSync.Media.UrlImportTest do
  use ExUnit.Case, async: false
  alias NobarSync.Media.UrlImport
  @base "https://93.184.216.34"
  @video <<0, 0, 0, 32, "ftypisom", 0, 0, 2, 0>>
  setup do
    vars = Map.new(["IMPORT_HOST_ALLOWLIST", "IMPORT_MAX_BYTES"], &{&1, System.get_env(&1)})
    old = Application.get_env(:nobarsync, :url_import_http_client)
    System.put_env("IMPORT_HOST_ALLOWLIST", "93.184.216.34,127.0.0.1")
    System.put_env("IMPORT_MAX_BYTES", "100000")
    Application.put_env(:nobarsync, :url_import_http_client, NobarSync.Media.UrlImportTest.Http)

    on_exit(fn ->
      Enum.each(vars, fn {key, value} ->
        if value, do: System.put_env(key, value), else: System.delete_env(key)
      end)

      if old,
        do: Application.put_env(:nobarsync, :url_import_http_client, old),
        else: Application.delete_env(:nobarsync, :url_import_http_client)
    end)

    :ok
  end

  defp respond(responses), do: Process.put(:import_responses, responses)
  defp video, do: {206, [{"content-type", "video/mp4"}], [@video]}

  test "keeps opaque query keys and supports files without extensions" do
    respond([video()])
    url = @base <> "/video?key=a%2Bb&part=1"
    assert {:ok, ^url} = UrlImport.resolve(url)
  end

  test "resolves HTML5 source and decodes query separator entities" do
    respond([
      {200, [{"content-type", "text/html"}],
       [~s(<html><video><source src='/video?key=x&amp;v=2'></video></html>)]},
      video()
    ])

    assert {:ok, url} = UrlImport.resolve(@base <> "/?key=x")
    assert url == @base <> "/video?key=x&v=2"
  end

  test "does not run player JavaScript or treat iframes as video" do
    respond([
      {200, [{"content-type", "text/html"}],
       [
         ~s(<html><iframe src='/player'></iframe><script>var t='<video src="/fake">';</script></html>)
       ]}
    ])

    assert {:error, :unsupported_player_page} = UrlImport.resolve(@base)
  end

  test "checks source hosts from HTML and redirect destinations" do
    respond([
      {200, [{"content-type", "text/html"}],
       [~s(<html><video src='https://not-allowed.example/video'></video></html>)]}
    ])

    assert {:error, :source_host_not_allowed} = UrlImport.resolve(@base)
    respond([{302, [{"location", "https://127.0.0.1/secret"}], []}])
    assert {:error, :forbidden_source} = UrlImport.resolve(@base)
  end

  test "rejects malformed input, credentials, ports and pasted quotes" do
    for url <- [
          nil,
          %{},
          "http://example.com/video",
          @base <> "/x\"",
          "https://user:pass@93.184.216.34/video",
          @base <> ":444/video"
        ] do
      assert {:error, :invalid_source_url} = UrlImport.resolve(url)
    end
  end

  test "rejects oversized Content-Range total before importing" do
    respond([
      {206, [{"content-type", "video/mp4"}, {"content-range", "bytes 0-15/999999"}], [@video]}
    ])

    assert {:error, :source_too_large} = UrlImport.resolve(@base)
  end

  test "rejects HLS playlists instead of passing remote references to ffprobe" do
    respond([{200, [{"content-type", "application/vnd.apple.mpegurl"}], ["#EXTM3U\nsegment.ts"]}])
    assert {:error, :unsupported_source_type} = UrlImport.resolve(@base)
  end

  test "streams download to disk and removes partial files over limit" do
    dest = Path.join(System.tmp_dir!(), "import-test-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm(dest) end)
    respond([video(), {200, [{"content-type", "video/mp4"}], [@video, "more"]}])
    assert {:ok, ^dest} = UrlImport.download(@base <> "/video", dest)
    assert File.read!(dest) == @video <> "more"
    System.put_env("IMPORT_MAX_BYTES", "20")

    respond([
      video(),
      {200, [{"content-type", "video/mp4"}], [@video, String.duplicate("a", 21)]}
    ])

    assert {:error, :source_too_large} = UrlImport.download(@base <> "/video", dest)
    refute File.exists?(dest)
  end
end
