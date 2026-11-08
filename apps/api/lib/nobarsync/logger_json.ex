defmodule NobarSync.LoggerJSON do
  @moduledoc false

  @redacted ~w(token authorization cookie password csrf media_token)a

  def format(level, message, timestamp, metadata) do
    metadata = redact(metadata)

    payload = %{
      time: format_time(timestamp),
      level: level,
      message: IO.iodata_to_binary(message),
      request_id: metadata[:request_id],
      room_id: metadata[:room_id]
    }

    [Jason.encode!(payload), "\n"]
  rescue
    _ -> [IO.iodata_to_binary(message), "\n"]
  end

  defp format_time({date, {h, m, s, ms}}) do
    {date, {h, m, s}}
    |> NaiveDateTime.from_erl!({div(ms, 1000), rem(ms, 1000) * 1000})
    |> NaiveDateTime.to_iso8601()
  end

  def redact(metadata) do
    Enum.reject(metadata, fn {key, _} -> key in @redacted end)
  end
end
