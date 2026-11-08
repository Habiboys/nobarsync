defmodule NobarSync.Media.HlsEncoderTest do
  use ExUnit.Case, async: false

  alias NobarSync.Media.HlsEncoder

  test "a 360p source stays on one rung" do
    assert [%{name: "360p", height: 360}] = HlsEncoder.ladders(360, 640)
  end

  test "a 1080p source is not upscaled and includes 720 and 480" do
    names = HlsEncoder.ladders(1080, 1920) |> Enum.map(& &1.name)
    assert names == ["1080p", "720p", "480p"]
  end

  @tag :ffmpeg
  test "encodes a two second fixture to fMP4 HLS" do
    dir = Path.join(System.tmp_dir!(), "nobarsync-hls-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    source = Path.join(dir, "source.mp4")

    {_, 0} =
      System.cmd(
        "ffmpeg",
        [
          "-y",
          "-f",
          "lavfi",
          "-i",
          "testsrc=size=640x360:rate=30",
          "-f",
          "lavfi",
          "-i",
          "sine=frequency=440",
          "-t",
          "2",
          "-shortest",
          "-c:v",
          "libx264",
          "-pix_fmt",
          "yuv420p",
          "-c:a",
          "aac",
          source
        ],
        stderr_to_stdout: true
      )

    assert {:ok, meta} = HlsEncoder.probe(source)
    out = Path.join(dir, "hls")
    assert {:ok, ladders} = HlsEncoder.encode(source, out, meta)
    assert Enum.map(ladders, & &1.height) == [360]
    assert File.exists?(Path.join(out, "master.m3u8"))
    assert File.read!(Path.join(out, "master.m3u8")) =~ "360p.m3u8"
    File.rm_rf!(dir)
  end
end
