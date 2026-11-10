defmodule NobarSyncWeb.FallbackController do
  use NobarSyncWeb, :controller

  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    conn
    |> put_status(422)
    |> json(%{
      error: %{
        code: "invalid",
        message: "Data tidak valid",
        details:
          Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
            Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
              opts
              |> Enum.find_value(key, fn {opt, value} ->
                if Atom.to_string(opt) == key, do: to_string(value)
              end)
            end)
          end)
      }
    })
  end

  def call(conn, {:error, :not_found}), do: error(conn, 404, "not_found", "Tidak ditemukan")

  def call(conn, {:error, :unauthorized}),
    do: error(conn, 401, "unauthorized", "Login diperlukan")

  def call(conn, {:error, :forbidden}), do: error(conn, 403, "forbidden", "Tidak diizinkan")

  def call(conn, {:error, :account_suspended}),
    do: error(conn, 403, "account_suspended", "Akun dinonaktifkan. Hubungi admin.")

  def call(conn, {:error, :invalid_credentials}),
    do: error(conn, 401, "invalid_credentials", "Email atau kata sandi salah")

  def call(conn, {:error, :invalid}), do: error(conn, 422, "invalid", "Data tidak valid")

  def call(conn, {:error, {:invalid, message}}) when is_binary(message),
    do: error(conn, 422, "invalid", message)

  def call(conn, {:error, :expired}), do: error(conn, 410, "expired", "Kedaluwarsa")
  def call(conn, {:error, :room_locked}), do: error(conn, 403, "room_locked", "Room dikunci")
  def call(conn, {:error, :room_full}), do: error(conn, 403, "room_full", "Room penuh")

  def call(conn, {:error, :media_not_ready}),
    do: error(conn, 409, "media_not_ready", "Media belum siap")

  def call(conn, {:error, :csrf}), do: error(conn, 403, "csrf", "CSRF tidak valid")
  def call(conn, {:error, {:disabled, message}}), do: error(conn, 501, "disabled", message)

  def call(conn, {:error, :not_implemented}),
    do: error(conn, 501, "not_implemented", "Belum tersedia")

  def call(conn, {:error, :forbidden_source}),
    do: error(conn, 403, "forbidden", "Sumber URL tidak diizinkan")

  def call(conn, {:error, :invalid_source_url}),
    do:
      error(
        conn,
        422,
        "invalid_source_url",
        "Masukkan URL HTTPS yang lengkap, tanpa tanda kutip atau spasi tambahan."
      )

  def call(conn, {:error, :source_host_not_allowed}),
    do:
      error(
        conn,
        403,
        "source_host_not_allowed",
        "Domain sumber belum diizinkan. Admin perlu menambahkannya ke IMPORT_HOST_ALLOWLIST pada API dan worker."
      )

  def call(conn, {:error, :unsupported_player_page}),
    do:
      error(
        conn,
        422,
        "unsupported_player_page",
        "Tautan ini membuka halaman player yang tidak menyediakan sumber video HTML5 langsung. Gunakan URL berkas video dari penyedia atau unggah berkasnya."
      )

  def call(conn, {:error, :unsupported_source_type}),
    do:
      error(
        conn,
        422,
        "unsupported_source_type",
        "Sumber bukan berkas video yang didukung. Gunakan MP4, WebM, MKV, atau berkas video lain; playlist HLS/DASH dan iframe belum didukung untuk impor."
      )

  def call(conn, {:error, :source_too_large}),
    do:
      error(
        conn,
        422,
        "source_too_large",
        "Ukuran video melebihi batas impor server (IMPORT_MAX_BYTES)."
      )

  def call(conn, {:error, :source_unreachable}),
    do:
      error(
        conn,
        422,
        "source_unreachable",
        "Sumber video tidak dapat diakses oleh server. Pastikan tautan masih aktif dan tidak memerlukan login."
      )

  def call(conn, {:error, :too_many_redirects}),
    do:
      error(
        conn,
        422,
        "too_many_redirects",
        "Tautan sumber terlalu banyak mengalihkan alamat. Gunakan URL video akhirnya."
      )

  defp error(conn, status, code, message) do
    conn |> put_status(status) |> json(%{error: %{code: code, message: message, details: %{}}})
  end
end
