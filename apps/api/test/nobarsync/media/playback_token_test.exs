defmodule NobarSync.Media.PlaybackTokenTest do
  use ExUnit.Case, async: true

  alias NobarSync.Media.PlaybackToken

  @secret "test-secret"
  @claims %{
    exp: 2_000_000_000,
    media_id: "11111111-1111-1111-1111-111111111111",
    prefix: "videos/11111111-1111-1111-1111-111111111111/",
    room_id: "22222222-2222-2222-2222-222222222222",
    scope: "playback"
  }

  test "round trip and shared vector" do
    assert PlaybackToken.canonical(@claims) ==
             ~s({"exp":2000000000,"media_id":"11111111-1111-1111-1111-111111111111","prefix":"videos/11111111-1111-1111-1111-111111111111/","room_id":"22222222-2222-2222-2222-222222222222","scope":"playback"})

    token = PlaybackToken.sign(@claims, @secret)
    assert {:ok, claims} = PlaybackToken.verify(token, @secret)
    assert claims["media_id"] == @claims.media_id
    assert :ok = PlaybackToken.authorize_path(claims, @claims.prefix <> "hls/master.m3u8")

    assert {:error, :forbidden} =
             PlaybackToken.authorize_path(claims, "videos/other/hls/master.m3u8")

    assert {:error, :invalid} =
             PlaybackToken.authorize_path(claims, @claims.prefix <> "../secret")

    assert {:error, :invalid} = PlaybackToken.verify(token <> "x", @secret)
  end

  test "expired token is rejected" do
    token = PlaybackToken.sign(%{@claims | exp: 10}, @secret)
    assert {:error, :expired} = PlaybackToken.verify(token, @secret)
  end
end
