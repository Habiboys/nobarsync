defmodule NobarSync.Media.StorageTest do
  use ExUnit.Case, async: false

  @tag :minio
  test "puts and reads a private object" do
    key = "videos/test/#{System.unique_integer([:positive])}.txt"
    assert {:ok, _} = NobarSync.Media.Storage.put(key, "halo", "text/plain")
    assert {:ok, %{body: body}} = NobarSync.Media.Storage.get(key)
    assert body == "halo"
    assert :ok = NobarSync.Media.Storage.delete_prefix("videos/test/")
  end
end
