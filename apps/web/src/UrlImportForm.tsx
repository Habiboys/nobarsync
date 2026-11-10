import { useState } from "react"
import { useQueryClient } from "@tanstack/react-query"
import { api } from "./api"
import { Button, Field } from "./ui"

export function UrlImportForm({ title, audience, busy, setBusy }: { title: string; audience: string; busy: boolean; setBusy: (value: boolean) => void }) {
  const client = useQueryClient()
  const [error, setError] = useState("")
  const [notice, setNotice] = useState("")
  async function submit(url: string) {
    setError(""); setNotice(""); setBusy(true)
    try {
      await api("/api/v1/media/import-url", { method: "POST", body: JSON.stringify({ url, title: title.trim() || "Impor video", audience }) })
      setNotice(audience === "library" ? "Impor masuk antrean. Setelah diolah, film menunggu persetujuan admin." : "Impor masuk antrean pengolahan, hanya untuk kamu.")
      await client.invalidateQueries({ queryKey: ["media"] })
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Impor gagal. Coba lagi.")
    } finally { setBusy(false) }
  }
  return <form className="mt-5 space-y-3" aria-busy={busy} onSubmit={event => {
    event.preventDefault()
    if (!busy) void submit(String(new FormData(event.currentTarget).get("source_url") || "").trim())
  }}>
    <Field label="URL video langsung" name="source_url" type="url" required disabled={busy} placeholder="https://domain-diizinkan/video.mp4" aria-describedby="import-help" />
    <p id="import-help" className="form-note">Gunakan URL berkas video atau halaman dengan video HTML5 langsung. Domain sumber dan tujuan pengalihannya harus diizinkan admin. Halaman yang memerlukan script, iframe, atau login belum didukung. Untuk YouTube, pilih sumber YouTube.</p>
    <p className="form-note">Server mengunduh dan mengolah video menjadi HLS. Film baru siap diputar setelah proses selesai.</p>
    {error ? <p role="alert">{error}</p> : null}
    {notice ? <p role="status">{notice}</p> : null}
    <Button type="submit" disabled={busy}>{busy ? "Memeriksa sumber…" : "Impor video"}</Button>
  </form>
}
