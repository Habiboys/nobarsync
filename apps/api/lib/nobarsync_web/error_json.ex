defmodule NobarSyncWeb.ErrorJSON do
  def render("404.json", _assigns) do
    %{error: %{code: "not_found", message: "Tidak ditemukan", details: %{}}}
  end

  def render("500.json", _assigns) do
    %{error: %{code: "internal", message: "Terjadi kesalahan", details: %{}}}
  end

  def render(_template, _assigns) do
    %{error: %{code: "error", message: "Permintaan gagal", details: %{}}}
  end
end
