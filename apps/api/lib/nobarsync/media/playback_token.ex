defmodule NobarSync.Media.PlaybackToken do
  @moduledoc false

  def sign(claims, secret) when is_binary(secret) do
    payload = canonical(claims) |> Base.url_encode64(padding: false)
    sig = :crypto.mac(:hmac, :sha256, secret, payload) |> Base.url_encode64(padding: false)
    payload <> "." <> sig
  end

  def verify(token, secret) when is_binary(token) and is_binary(secret) do
    case String.split(token, ".", parts: 2) do
      [payload, sig] ->
        expected =
          :crypto.mac(:hmac, :sha256, secret, payload) |> Base.url_encode64(padding: false)

        if byte_size(sig) == byte_size(expected) and Plug.Crypto.secure_compare(sig, expected) do
          decode_payload(payload)
        else
          {:error, :invalid}
        end

      _ ->
        {:error, :invalid}
    end
  end

  def authorize_path(%{"prefix" => prefix, "exp" => exp}, object_key) do
    now = System.system_time(:second)

    cond do
      not is_integer(exp) or exp < now -> {:error, :expired}
      not safe_key?(object_key) -> {:error, :invalid}
      not String.starts_with?(object_key, prefix) -> {:error, :forbidden}
      true -> :ok
    end
  end

  def canonical(%{exp: exp, media_id: media_id, prefix: prefix, room_id: room_id, scope: scope}) do
    ~s({"exp":#{exp},"media_id":"#{media_id}","prefix":"#{prefix}","room_id":#{json_string(room_id)},"scope":"#{scope}"})
  end

  defp decode_payload(payload) do
    with {:ok, json} <- Base.url_decode64(payload, padding: false),
         {:ok, claims} <- Jason.decode(json) do
      if claims["exp"] < System.system_time(:second), do: {:error, :expired}, else: {:ok, claims}
    else
      _ -> {:error, :invalid}
    end
  end

  defp json_string(nil), do: "null"
  defp json_string(value), do: ~s("#{value}")

  defp safe_key?(key) do
    is_binary(key) and not String.contains?(key, ["..", "\\", "\0"]) and
      not String.starts_with?(key, "/")
  end
end
