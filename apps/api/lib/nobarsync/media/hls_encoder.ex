defmodule NobarSync.Media.HlsEncoder do
  @moduledoc false

  def probe(path) do
    case System.cmd("ffprobe", [
           "-v",
           "error",
           "-print_format",
           "json",
           "-show_format",
           "-show_streams",
           path
         ]) do
      {output, 0} ->
        case Jason.decode(output) do
          {:ok, json} -> {:ok, summarize(json)}
          _ -> {:error, :probe_failed}
        end

      {output, _} ->
        {:error, {:probe_failed, String.slice(output, 0, 500)}}
    end
  end

  def encode(input, output_dir, meta, on_progress \\ fn _ratio -> :ok end) do
    File.mkdir_p!(output_dir)
    ladders = ladders(meta.height || 0, meta.width || 0)
    fps = meta.fps || 30
    gop = max(trunc(fps * 4), 24)
    threads = System.get_env("ENCODE_THREADS") || "2"
    filter = filter_complex(ladders)
    maps = map_args(ladders, meta.has_audio)
    var_map = var_stream_map(ladders, meta.has_audio)

    args =
      ["-y", "-i", input, "-threads", threads, "-filter_complex", filter] ++
        maps ++
        [
          "-c:v",
          "libx264",
          "-preset",
          "veryfast",
          "-pix_fmt",
          "yuv420p",
          "-g",
          Integer.to_string(gop),
          "-keyint_min",
          Integer.to_string(gop),
          "-sc_threshold",
          "0",
          "-force_key_frames",
          "expr:gte(t,n_forced*4)"
        ] ++
        bitrate_args(ladders) ++
        audio_args(meta.has_audio) ++
        [
          "-f",
          "hls",
          "-hls_time",
          "4",
          "-hls_playlist_type",
          "vod",
          "-hls_segment_type",
          "fmp4",
          "-hls_fmp4_init_filename",
          "init.mp4",
          "-hls_flags",
          "independent_segments",
          "-master_pl_name",
          "master.m3u8",
          "-var_stream_map",
          var_map,
          "-hls_segment_filename",
          Path.join(output_dir, "%v/segment_%05d.m4s"),
          Path.join(output_dir, "%v.m3u8")
        ]

    case run_ffmpeg(args, meta.duration_ms || 0, on_progress) do
      :ok ->
        rewrite_segment_uris(output_dir)
        {:ok, ladders}

      other ->
        other
    end
  end

  defp run_ffmpeg(args, duration_ms, on_progress) do
    port =
      Port.open({:spawn_executable, System.find_executable("ffmpeg")}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        args: args
      ])

    collect_ffmpeg(port, "", duration_ms, on_progress, 0)
  end

  defp collect_ffmpeg(port, buffer, duration_ms, on_progress, last_mark) do
    receive do
      {^port, {:data, chunk}} ->
        text = buffer <> chunk
        {ready, rest} = split_progress(text)

        marked =
          Enum.reduce(ready, last_mark, fn line, acc ->
            note_progress(line, duration_ms, on_progress, acc)
          end)

        collect_ffmpeg(port, rest, duration_ms, on_progress, marked)

      {^port, {:exit_status, 0}} ->
        on_progress.(1.0)
        :ok

      {^port, {:exit_status, code}} ->
        {:error, {:ffmpeg, code, String.slice(buffer, -800, 800)}}
    after
      1_800_000 ->
        Port.close(port)
        {:error, :timeout}
    end
  end

  defp split_progress(text) do
    parts = String.split(text, ~r/\r|\n/)
    {Enum.drop(parts, -1), List.last(parts) || ""}
  end

  defp note_progress(line, duration_ms, on_progress, last_mark) do
    case Regex.run(~r/time=(\d+):(\d+):(\d+(?:\.\d+)?)/, line) do
      [_, hours, minutes, seconds] ->
        seen =
          (String.to_integer(hours) * 3600 + String.to_integer(minutes) * 60) * 1000 +
            trunc(String.to_float(seconds) * 1000)

        ratio = if duration_ms > 0, do: min(seen / duration_ms, 0.99), else: 0.0
        now = System.system_time(:millisecond)
        if now - last_mark > 2_000, do: on_progress.(ratio)
        if now - last_mark > 2_000, do: now, else: last_mark

      _ ->
        last_mark
    end
  end

  def poster(input, dest) do
    File.mkdir_p!(Path.dirname(dest))

    case System.cmd(
           "ffmpeg",
           ["-y", "-ss", "1", "-i", input, "-frames:v", "1", "-vf", "scale=640:-2", dest],
           stderr_to_stdout: true
         ) do
      {_, 0} -> :ok
      _ -> :error
    end
  end

  def previews(input, dir) do
    File.mkdir_p!(dir)

    System.cmd(
      "ffmpeg",
      [
        "-y",
        "-i",
        input,
        "-vf",
        "fps=1/2,scale=320:-2",
        "-frames:v",
        "6",
        Path.join(dir, "preview_%03d.webp")
      ],
      stderr_to_stdout: true
    )

    Path.wildcard(Path.join(dir, "preview_*.webp"))
  end

  def subtitles(input, dir) do
    File.mkdir_p!(dir)

    case probe(input) do
      {:ok, %{subtitle_streams: streams}} ->
        streams
        |> Enum.with_index()
        |> Enum.flat_map(fn {stream, index} ->
          lang = get_in(stream, ["tags", "language"]) || "und"
          dest = Path.join(dir, "#{lang}-#{index}.vtt")

          case System.cmd("ffmpeg", ["-y", "-i", input, "-map", "0:s:#{index}", dest],
                 stderr_to_stdout: true
               ) do
            {_, 0} -> [%{language: lang, label: lang, path: dest}]
            _ -> []
          end
        end)

      _ ->
        []
    end
  end

  def ladders(height, _width) do
    cond do
      height >= 1080 ->
        [
          %{name: "1080p", height: 1080, bitrate: "5000k"},
          %{name: "720p", height: 720, bitrate: "2500k"},
          %{name: "480p", height: 480, bitrate: "1000k"}
        ]

      height >= 720 ->
        [
          %{name: "720p", height: 720, bitrate: "2500k"},
          %{name: "480p", height: 480, bitrate: "1000k"}
        ]

      height >= 480 ->
        [%{name: "480p", height: 480, bitrate: "1000k"}]

      height > 0 ->
        [%{name: "#{height}p", height: height, bitrate: "800k"}]

      true ->
        [%{name: "source", height: -2, bitrate: "1000k"}]
    end
  end

  defp summarize(json) do
    streams = json["streams"] || []
    video = Enum.find(streams, &(&1["codec_type"] == "video")) || %{}
    audio = Enum.any?(streams, &(&1["codec_type"] == "audio"))
    duration = parse_duration(json["format"]["duration"] || video["duration"])

    %{
      width: video["width"],
      height: video["height"],
      duration_ms: duration,
      fps: parse_fps(video["avg_frame_rate"]),
      has_audio: audio,
      subtitle_streams: Enum.filter(streams, &(&1["codec_type"] == "subtitle")),
      format: json["format"]["format_name"]
    }
  end

  defp parse_duration(nil), do: 0
  defp parse_duration(value), do: trunc(parse_number(value) * 1000)

  defp parse_fps(nil), do: 30
  defp parse_fps("0/0"), do: 30

  defp parse_fps(value) do
    case String.split(to_string(value), "/") do
      [num, den] ->
        den_f = parse_number(den)
        if den_f == 0, do: 30.0, else: parse_number(num) / den_f

      _ ->
        30.0
    end
  end

  defp parse_number(value) do
    case Float.parse(to_string(value)) do
      {number, _} -> number
      :error -> 0.0
    end
  end

  defp rewrite_segment_uris(output_dir) do
    output_dir
    |> Path.join("*.m3u8")
    |> Path.wildcard()
    |> Enum.reject(&String.ends_with?(&1, "master.m3u8"))
    |> Enum.each(fn path ->
      name = Path.basename(path, ".m3u8")

      fixed =
        path
        |> File.read!()
        |> String.replace(~r/^(segment_\d+\.m4s)$/m, "#{name}/\\1")

      File.write!(path, fixed)
    end)
  end

  defp filter_complex(ladders) do
    split = Enum.map_join(ladders, "", fn ladder -> "[v#{ladder.name}]" end)

    scales =
      Enum.map_join(ladders, ";", fn ladder ->
        "[v#{ladder.name}]scale=-2:#{ladder.height}:flags=lanczos[o#{ladder.name}]"
      end)

    "[0:v]split=#{length(ladders)}#{split};#{scales}"
  end

  defp map_args(ladders, has_audio) do
    Enum.flat_map(ladders, fn ladder ->
      video = ["-map", "[o#{ladder.name}]"]
      if has_audio, do: video ++ ["-map", "0:a:0"], else: video
    end)
  end

  defp bitrate_args(ladders) do
    ladders
    |> Enum.with_index()
    |> Enum.flat_map(fn {ladder, index} -> ["-b:v:#{index}", ladder.bitrate] end)
  end

  defp var_stream_map(ladders, has_audio) do
    ladders
    |> Enum.with_index()
    |> Enum.map_join(" ", fn {ladder, index} ->
      audio = if has_audio, do: ",a:#{index}", else: ""
      "v:#{index}#{audio},name:#{ladder.name}"
    end)
  end

  defp audio_args(true), do: ["-c:a", "aac", "-ac", "2", "-b:a", "128k", "-ar", "48000"]
  defp audio_args(false), do: ["-an"]
end
