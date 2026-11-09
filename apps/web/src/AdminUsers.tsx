import { useEffect, useRef, useState } from "react"
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query"
import { api } from "./api"
import { Button, Field, Panel } from "./ui"

type ManagedUser = { id: string; email: string; display_name: string; role: string; status: string; plan: string; inserted_at: string }

export function AdminUsers({ me }: { me: string }) {
  const client = useQueryClient()
  const drawer = useRef<HTMLDialogElement>(null)
  const [search, setSearch] = useState("")
  const [query, setQuery] = useState("")
  const [status, setStatus] = useState("")
  const [role, setRole] = useState("")
  const [page, setPage] = useState(1)
  const [selected, setSelected] = useState<ManagedUser | null>(null)
  const [reason, setReason] = useState("")
  const [error, setError] = useState("")
  useEffect(() => {
    const timer = window.setTimeout(() => { setQuery(search); setPage(1) }, 250)
    return () => window.clearTimeout(timer)
  }, [search])
  useEffect(() => {
    if (selected && !drawer.current?.open) drawer.current?.showModal()
    else if (!selected && drawer.current?.open) drawer.current.close()
  }, [selected])
  const users = useQuery({
    queryKey: ["admin", "users", query, status, role, page],
    queryFn: () => api<{ users: ManagedUser[]; total: number; page: number; per_page: number }>(`/api/v1/admin/users?${new URLSearchParams({ search: query, status, role, page: String(page) })}`),
  })
  const mutation = useMutation({
    mutationFn: ({ user, revoke }: { user: ManagedUser; revoke: boolean }) => api(`/api/v1/admin/users/${user.id}${revoke ? "/revoke-sessions" : ""}`, {
      method: revoke ? "POST" : "PATCH",
      body: JSON.stringify({ display_name: user.display_name, role: user.role, status: user.status, reason }),
    }),
    onSuccess: async () => { setSelected(null); setReason(""); setError(""); await client.invalidateQueries({ queryKey: ["admin"] }) },
    onError: (failure: Error) => setError(failure.message),
  })
  return <>
    <Panel title="Pengguna" subtitle="Kelola akses akun. Semua akun menggunakan layanan gratis.">
      <div className="admin-filters">
        <label className="field"><span>Cari pengguna</span><input placeholder="Nama atau email" value={search} onChange={e => setSearch(e.target.value)} /></label>
        <label className="field"><span>Status akun</span><select aria-label="Filter status akun" value={status} onChange={e => { setStatus(e.target.value); setPage(1) }}><option value="">Semua status</option><option value="active">Aktif</option><option value="suspended">Disuspensi</option></select></label>
        <label className="field"><span>Peran</span><select aria-label="Filter peran akun" value={role} onChange={e => { setRole(e.target.value); setPage(1) }}><option value="">Semua peran</option><option value="user">Pengguna</option><option value="admin">Admin</option></select></label>
      </div>
      {users.isPending ? <p role="status">Memuat daftar pengguna…</p> : null}
      {users.error ? <p role="alert">Daftar pengguna gagal dimuat: {users.error.message}</p> : null}
      {error && !selected ? <p role="alert">{error}</p> : null}
      <div className="table-scroll"><table className="data-table"><thead><tr><th>Akun</th><th>Peran</th><th>Status</th><th>Paket</th><th><span className="sr-only">Tindakan</span></th></tr></thead><tbody>{users.data?.users.map(user => <tr key={user.id}>
        <td><strong>{user.display_name}{user.id === me ? " (Anda)" : ""}</strong><small>{user.email}</small></td>
        <td>{user.role === "admin" ? "Admin" : "Pengguna"}</td><td><span className={`account-status ${user.status}`}>{user.status === "active" ? "Aktif" : "Disuspensi"}</span></td><td>Gratis</td>
        <td><Button tone="ghost" disabled={mutation.isPending} aria-label={`Kelola ${user.email}`} onClick={() => { setSelected({ ...user }); setReason(""); setError("") }}>Kelola</Button></td>
      </tr>)}</tbody></table></div>
      {users.data?.total === 0 ? <p className="empty-message">Tidak ada akun yang sesuai. Ubah pencarian atau filter.</p> : null}
      <div className="pagination"><span>{users.data?.total || 0} akun · halaman {page}</span><div><Button tone="ghost" disabled={page <= 1 || users.isFetching} onClick={() => setPage(page - 1)}>Sebelumnya</Button><Button tone="ghost" disabled={page * 20 >= (users.data?.total || 0) || users.isFetching} onClick={() => setPage(page + 1)}>Berikutnya</Button></div></div>
    </Panel>
    <dialog ref={drawer} className="account-drawer" aria-labelledby="account-drawer-title" onClose={() => setSelected(null)} onClick={event => { if (event.target === event.currentTarget) setSelected(null) }}>
      {selected ? <div className="drawer-content">
        <header className="drawer-header"><div><h2 id="account-drawer-title">Kelola akun</h2><p>{selected.email}</p></div><button type="button" className="secondary-button" aria-label="Tutup pengaturan akun" onClick={() => setSelected(null)}>Tutup</button></header>
        <form className="drawer-form" onSubmit={event => { event.preventDefault(); setError(""); mutation.mutate({ user: selected, revoke: false }) }}>
          <Field label="Nama pengguna" value={selected.display_name} minLength={2} maxLength={40} required onChange={e => setSelected({ ...selected, display_name: e.target.value })} />
          <label className="field"><span>Peran akun</span><select value={selected.role} disabled={selected.id === me} onChange={e => setSelected({ ...selected, role: e.target.value })}><option value="user">Pengguna</option><option value="admin">Admin</option></select></label>
          <label className="field"><span>Status akun</span><select value={selected.status} disabled={selected.id === me} onChange={e => setSelected({ ...selected, status: e.target.value })}><option value="active">Aktif</option><option value="suspended">Disuspensi</option></select></label>
          <label className="field"><span>Alasan tindakan</span><textarea minLength={3} maxLength={500} rows={3} required value={reason} onChange={e => setReason(e.target.value)} /></label>
          <p className="form-note">Perubahan peran atau status mencabut sesi dan koneksi aktif. Setelah diaktifkan kembali, pengguna perlu login lagi.</p>
          {selected.id === me ? <p className="form-note">Peran dan status akun Anda hanya dapat diubah oleh admin lain.</p> : null}
          {error ? <p role="alert">{error}</p> : null}
          <footer className="drawer-actions"><Button type="submit" disabled={mutation.isPending}>{mutation.isPending ? "Menyimpan…" : "Simpan akun"}</Button><Button type="button" tone="ghost" disabled={mutation.isPending || selected.id === me || reason.trim().length < 3} onClick={() => { setError(""); mutation.mutate({ user: selected, revoke: true }) }}>Cabut semua sesi</Button></footer>
        </form>
      </div> : null}
    </dialog>
  </>
}
