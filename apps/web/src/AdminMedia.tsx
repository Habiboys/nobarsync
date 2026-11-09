import { useEffect, useRef, useState } from "react"
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query"
import { api, type Media } from "./api"
import { Button, Field, Panel } from "./ui"

type ManagedMedia = Media & { description?: string | null; inserted_at: string; owner: { id: string; display_name: string; email: string } | null }

const statusLabel: Record<string, string> = { pending: "Unggahan belum selesai", ready: "Siap ditonton", processing: "Sedang diolah", probing: "Memeriksa video", queued: "Dalam antrean", uploading: "Sedang diunggah", failed: "Pengolahan gagal", cancelled: "Dibatalkan" }

export function AdminMedia() {
  const client = useQueryClient()
  const drawer = useRef<HTMLDialogElement>(null)
  const [search, setSearch] = useState("")
  const [query, setQuery] = useState("")
  const [status, setStatus] = useState("")
  const [visibility, setVisibility] = useState("")
  const [page, setPage] = useState(1)
  const [selected, setSelected] = useState<ManagedMedia | null>(null)
  const [reason, setReason] = useState("")
  const [confirmDelete, setConfirmDelete] = useState(false)
  const [error, setError] = useState("")
  useEffect(() => {
    const timer = window.setTimeout(() => { setQuery(search); setPage(1) }, 250)
    return () => window.clearTimeout(timer)
  }, [search])
  useEffect(() => {
    if (selected && !drawer.current?.open) drawer.current?.showModal()
    else if (!selected && drawer.current?.open) drawer.current.close()
  }, [selected])
  const media = useQuery({
    queryKey: ["admin", "media", query, status, visibility, page],
    queryFn: () => api<{ items: ManagedMedia[]; total: number; page: number; per_page: number }>(`/api/v1/admin/media?${new URLSearchParams({ search: query, status, visibility, page: String(page) })}`),
  })
  const done = async () => { setSelected(null); setReason(""); setError(""); setConfirmDelete(false); await client.invalidateQueries({ queryKey: ["admin"] }); await client.invalidateQueries({ queryKey: ["media"] }) }
  const save = useMutation({
    mutationFn: (item: ManagedMedia) => api(`/api/v1/admin/media/${item.id}`, { method: "PATCH", body: JSON.stringify({ title: item.title, description: item.description || "", visibility: item.visibility, reason }) }),
    onSuccess: done,
    onError: (failure: Error) => setError(failure.message),
  })
  const remove = useMutation({
    mutationFn: (item: ManagedMedia) => api(`/api/v1/admin/media/${item.id}`, { method: "DELETE", body: JSON.stringify({ reason }) }),
    onSuccess: done,
    onError: (failure: Error) => setError(failure.message),
  })
  const busy = save.isPending || remove.isPending
  const perPage = media.data?.per_page || 20
  function open(item: ManagedMedia) { setSelected({ ...item }); setReason(""); setError(""); setConfirmDelete(false) }
  return <>
    <Panel title="Film" subtitle="Semua film dari semua pengguna, termasuk yang pribadi. Perubahan dan penghapusan tercatat di jejak tindakan.">
      <div className="admin-filters">
        <label className="field"><span>Cari film</span><input placeholder="Judul, nama, atau email pemilik" value={search} onChange={e => setSearch(e.target.value)} /></label>
        <label className="field"><span>Status film</span><select aria-label="Filter status film" value={status} onChange={e => { setStatus(e.target.value); setPage(1) }}><option value="">Semua status</option><option value="ready">Siap ditonton</option><option value="processing">Sedang diolah</option><option value="pending">Unggahan belum selesai</option><option value="failed">Gagal</option></select></label>
        <label className="field"><span>Akses</span><select aria-label="Filter akses film" value={visibility} onChange={e => { setVisibility(e.target.value); setPage(1) }}><option value="">Semua akses</option><option value="private">Pribadi</option><option value="library">Pustaka bersama</option></select></label>
      </div>
      {media.isPending ? <p role="status">Memuat koleksi film…</p> : null}
      {media.error ? <p role="alert">Koleksi film gagal dimuat: {media.error.message}</p> : null}
      <div className="table-scroll"><table className="data-table"><thead><tr><th>Film</th><th>Pemilik</th><th>Status</th><th>Akses</th><th><span className="sr-only">Tindakan</span></th></tr></thead><tbody>{media.data?.items.map(item => <tr key={item.id}>
        <td><strong>{item.title}</strong><small>{item.provider === "youtube" ? "YouTube" : "Unggahan"} · {new Date(item.inserted_at).toLocaleDateString("id-ID", { timeZone: "Asia/Jakarta" })}</small></td>
        <td>{item.owner ? <><strong>{item.owner.display_name}</strong><small>{item.owner.email}</small></> : "Tanpa pemilik"}</td>
        <td>{statusLabel[item.status] || item.status}</td>
        <td>{item.visibility === "library" ? "Pustaka bersama" : "Pribadi"}</td>
        <td><Button tone="ghost" disabled={busy} aria-label={`Kelola ${item.title}`} onClick={() => open(item)}>Kelola</Button></td>
      </tr>)}</tbody></table></div>
      {media.data?.total === 0 ? <p className="empty-message">Tidak ada film yang sesuai. Ubah pencarian atau filter.</p> : null}
      <div className="pagination"><span>{media.data?.total || 0} film · halaman {page}</span><div><Button tone="ghost" disabled={page <= 1 || media.isFetching} onClick={() => setPage(page - 1)}>Sebelumnya</Button><Button tone="ghost" disabled={page * perPage >= (media.data?.total || 0) || media.isFetching} onClick={() => setPage(page + 1)}>Berikutnya</Button></div></div>
    </Panel>
    <dialog ref={drawer} className="account-drawer" aria-labelledby="media-drawer-title" onClose={() => setSelected(null)} onClick={event => { if (event.target === event.currentTarget) setSelected(null) }}>
      {selected ? <div className="drawer-content">
        <header className="drawer-header"><div><h2 id="media-drawer-title">Kelola film</h2><p>Milik {selected.owner ? `${selected.owner.display_name} (${selected.owner.email})` : "akun yang sudah dihapus"}</p></div><button type="button" className="secondary-button" aria-label="Tutup pengaturan film" onClick={() => setSelected(null)}>Tutup</button></header>
        <form className="drawer-form" onSubmit={event => { event.preventDefault(); setError(""); save.mutate(selected) }}>
          <Field label="Judul film" value={selected.title} minLength={1} maxLength={160} required onChange={e => setSelected({ ...selected, title: e.target.value })} />
          <label className="field"><span>Deskripsi</span><textarea rows={3} maxLength={2000} value={selected.description || ""} onChange={e => setSelected({ ...selected, description: e.target.value })} /></label>
          <label className="field"><span>Akses</span><select value={selected.visibility} onChange={e => setSelected({ ...selected, visibility: e.target.value })}><option value="private">Pribadi, hanya pemilik</option><option value="library">Pustaka bersama, semua pengguna</option></select></label>
          <label className="field"><span>Alasan tindakan</span><textarea minLength={3} maxLength={500} rows={3} required value={reason} onChange={e => setReason(e.target.value)} /></label>
          <p className="form-note">Alasan wajib diisi untuk menyimpan maupun menghapus, dan ikut tercatat di jejak tindakan.</p>
          {error ? <p role="alert">{error}</p> : null}
          <footer className="drawer-actions">
            <Button type="submit" disabled={busy}>{save.isPending ? "Menyimpan…" : "Simpan film"}</Button>
            {confirmDelete
              ? <><Button type="button" tone="danger" disabled={busy || reason.trim().length < 3} onClick={() => { setError(""); remove.mutate(selected) }}>{remove.isPending ? "Menghapus…" : "Hapus permanen"}</Button><Button type="button" tone="ghost" disabled={busy} onClick={() => setConfirmDelete(false)}>Batal</Button></>
              : <Button type="button" tone="ghost" disabled={busy} onClick={() => setConfirmDelete(true)}>Hapus film</Button>}
          </footer>
          {confirmDelete ? <p className="form-note" role="alert">File video, subtitle, dan sesi unggahan film ini ikut terhapus dan tidak bisa dikembalikan.</p> : null}
        </form>
      </div> : null}
    </dialog>
  </>
}
