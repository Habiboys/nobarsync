import { AdminConsole } from "./AdminConsole"
import { Brand } from "./Brand"
import { ThemeToggle } from "./ThemeToggle"
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query"
import { lazy, Suspense, useEffect, useRef, useState } from "react"
import type { ReactNode } from "react"
import { Link, NavLink, Navigate, useLocation, useNavigate, useParams, useSearchParams } from "react-router"
import { api } from "./api"
import type { Media, Member, Room } from "./api"
import { useSession } from "./session"
import { Button, Field, Panel } from "./ui"
import { useToasts } from "./toasts"
const MediaPreview = lazy(() => import("./MediaPreview"))

function Shell(props: { children: ReactNode }) {
  const session = useSession()
  const name = session.data?.user?.display_name
  const navigation = <>
    <NavLink to="/dashboard">Ruang saya</NavLink>
    <NavLink to="/library">Pustaka</NavLink>
    <NavLink to="/join">Gabung ruang</NavLink>
    {name ? <NavLink to="/profile">Akun</NavLink> : <NavLink to="/login">Masuk</NavLink>}
    {session.data?.user?.role === "admin" ? <NavLink to="/admin">Admin</NavLink> : null}
  </>
  return (
    <div className="app-shell">
      <a className="skip-link" href="#main-content">Lewati ke konten</a>
      <header className="app-header">
        <Brand />
        <nav className="desktop-nav" aria-label="Utama">{navigation}</nav>
        <div className="header-tools"><ThemeToggle /><details className="mobile-menu"><summary>Menu</summary><nav aria-label="Menu ponsel">{navigation}</nav></details></div>
      </header>
      <main id="main-content">{props.children}</main>
      <footer className="app-footer"><span>Manonton</span><span>Nonton bersama, gratis.</span></footer>
    </div>
  )
}

export function Landing() {
  return <Shell><section className="landing-intro"><h1>Malam ini,<em>manonton bareng.</em></h1><div><p>Pilih film, buat ruang, lalu bagikan kodenya ke teman. Host memimpin pemutaran, sementara kalian bisa chat dan bergantian bicara.</p><div className="landing-actions"><Link className="button button-primary" to="/rooms/new">Buat ruang nonton</Link><Link className="button button-ghost" to="/join">Gabung dengan kode</Link></div></div></section><p className="landing-note">Gunakan video unggahan sendiri atau player YouTube. Semua peserta perlu akun untuk bergabung. Saat call, tahan tombol bicara; suara film kembali setelah percakapan selesai.</p></Shell>
}

export function Login() {
  const navigate = useNavigate()
  const location = useLocation()
  const requested = new URLSearchParams(location.search).get("next") || "/dashboard"
  const next = requested.startsWith("/") && !requested.startsWith("//") && !requested.includes("\\") ? requested : "/dashboard"
  const client = useQueryClient()
  const push = useToasts((state) => state.push)
  const [email, setEmail] = useState("")
  const [password, setPassword] = useState("")
  const login = useMutation({
    mutationFn: () => api("/api/v1/auth/login", { method: "POST", body: JSON.stringify({ email, password }) }),
    onSuccess: async () => {
      await client.invalidateQueries({ queryKey: ["me"] })
      navigate(next, { replace: true })
    },
    onError: (error: Error) => push(error.message),
  })
  return (
    <Shell>
      <div className="page-heading"><div><h1>Masuk ke Manonton</h1><p>Lanjutkan ke ruang dan film Anda.</p></div></div><Panel className="max-w-md">
        <form className="space-y-3" onSubmit={(event) => { event.preventDefault(); login.mutate() }}>
          <Field label="Email" type="email" autoComplete="email" required value={email} onChange={(event) => setEmail(event.target.value)} />
          <Field label="Kata sandi" type="password" autoComplete="current-password" required value={password} onChange={(event) => setPassword(event.target.value)} />
          <Button type="submit" disabled={login.isPending}>{login.isPending ? "Memeriksa akun…" : "Masuk"}</Button>
          <p className="text-sm text-mist">Belum punya akun? <Link to={`/register?next=${encodeURIComponent(next)}`}>Daftar</Link></p>
        </form>
      </Panel>
    </Shell>
  )
}

export function Register() {
  const navigate = useNavigate()
  const location = useLocation()
  const requested = new URLSearchParams(location.search).get("next") || "/dashboard"
  const next = requested.startsWith("/") && !requested.startsWith("//") && !requested.includes("\\") ? requested : "/dashboard"
  const client = useQueryClient()
  const push = useToasts((state) => state.push)
  const [displayName, setDisplayName] = useState("")
  const [email, setEmail] = useState("")
  const [password, setPassword] = useState("")
  const register = useMutation({
    mutationFn: () => api("/api/v1/auth/register", { method: "POST", body: JSON.stringify({ email, password, display_name: displayName }) }),
    onSuccess: async () => {
      await client.invalidateQueries({ queryKey: ["me"] })
      navigate(next, { replace: true })
    },
    onError: (error: Error) => push(error.message),
  })
  return (
    <Shell>
      <div className="page-heading"><div><h1>Buat akun</h1><p>Satu akun untuk ruang dan pustaka Anda. Gratis.</p></div></div><Panel className="max-w-md">
        <form className="space-y-3" onSubmit={(event) => { event.preventDefault(); register.mutate() }}>
          <Field label="Nama" autoComplete="name" required minLength={2} maxLength={40} value={displayName} onChange={(event) => setDisplayName(event.target.value)} />
          <Field label="Email" type="email" autoComplete="email" required value={email} onChange={(event) => setEmail(event.target.value)} />
          <Field label="Kata sandi" type="password" autoComplete="new-password" required minLength={8} maxLength={72} value={password} onChange={(event) => setPassword(event.target.value)} />
          <p className="form-note">Gunakan setidaknya 8 karakter untuk kata sandi.</p><Button type="submit" disabled={register.isPending}>{register.isPending ? "Membuat akun…" : "Buat akun"}</Button><p className="text-sm text-mist">Sudah punya akun? <Link to={`/login?next=${encodeURIComponent(next)}`}>Masuk</Link></p>
        </form>
      </Panel>
    </Shell>
  )
}

export function Dashboard() {
  const session = useSession()
  const navigate = useNavigate()
  const client = useQueryClient()
  const push = useToasts((state) => state.push)
  const [code, setCode] = useState("")
  async function joinRoom() {
    const next = code.trim().toUpperCase()
    if (next.length < 4) {
      push("Isi kode ruang.")
      return
    }
    try {
      const joined = await api<{ member: { role: string } }>(`/api/v1/rooms/${next}/join`, { method: "POST", body: "{}" })
      navigate(joined.member.role === "viewer" ? `/watch/${next}` : `/rooms/${next}`)
    } catch (error) {
      push(error instanceof Error ? error.message : "Gagal gabung")
    }
  }
  const rooms = useQuery({
    queryKey: ["dashboard"],
    queryFn: () => api<{ active: Room[]; history: Room[] }>("/api/v1/rooms"),
    enabled: Boolean(session.data?.user),
  })
  async function mutateRoom(room: Room, action: "close" | "delete") {
    const verb = action === "close" ? "Tutup" : "Hapus"
    if (!window.confirm(`${verb} ruang ${room.title}?`)) return
    try {
      if (action === "close") await api(`/api/v1/rooms/${room.code}/close`, { method: "POST", body: "{}" })
      else await api(`/api/v1/rooms/${room.code}`, { method: "DELETE" })
      await client.invalidateQueries({ queryKey: ["dashboard"] })
    } catch (error) {
      push(error instanceof Error ? error.message : "Gagal mengubah ruang")
    }
  }
  if (session.isLoading) return <Shell><p>Memuat...</p></Shell>
  if (!session.data?.user) return <Navigate to="/login" />
  const seen = new Set<string>()
  const listed = [...(rooms.data?.active || []), ...(rooms.data?.history || [])].filter((room) => {
    if (seen.has(room.id)) return false
    seen.add(room.id)
    return true
  })
  return (
    <Shell>
      <div className="dashboard-heading"><div><h1>Ruang nonton Anda</h1><p>Halo, {session.data.user.display_name}. Lanjutkan ruang yang ada atau pilih film untuk ruang baru.</p></div><Link className="button button-primary" to="/rooms/new">Buat ruang</Link></div>
      <form className="join-code" onSubmit={(event) => { event.preventDefault(); void joinRoom() }}>
        <label className="field"><span>Punya undangan?</span><input aria-label="Kode ruang" placeholder="Masukkan kode ruang" autoCapitalize="characters" value={code} onChange={(event) => setCode(event.target.value)} /></label>
        <Button type="submit">Gabung</Button>
      </form>
      {rooms.error instanceof Error ? <p className="mb-4 text-sm text-amber">{rooms.error.message}</p> : null}
      {rooms.isPending ? <p role="status" className="empty-message">Memuat ruang Anda…</p> : null}
      <div className="room-list">
        {listed.map((room) => (
          <article key={room.id} className="room-card">
            <Link to={`/rooms/${room.code}`}>
              <p className="room-code">{room.code}</p>
              <h2>{room.title}</h2>
              <p className="text-sm text-mist">{room.status === "open" ? "Masih terbuka" : "Ditutup"}</p>
            </Link>
            <div className="room-actions">
              <Link className="button button-ghost" to={`/rooms/${room.code}`}>{room.status === "open" ? "Masuk ruang" : "Lihat"}</Link>
              {room.host_user_id === session.data?.user?.id && room.status === "open" ? <Button tone="ghost" onClick={() => mutateRoom(room, "close")}>Tutup</Button> : null}
              {room.host_user_id === session.data?.user?.id ? <Button tone="ghost" onClick={() => mutateRoom(room, "delete")}>Hapus</Button> : null}
            </div>
          </article>
        ))}
        {!rooms.isPending && !rooms.error && listed.length === 0 ? <p className="empty-message">Belum ada ruang. Buat ruang baru atau masukkan kode undangan teman.</p> : null}
      </div>
    </Shell>
  )
}

export function Library() {
  const session = useSession()
  const client = useQueryClient()
  const push = useToasts((state) => state.push)
  const [q, setQ] = useState("")
  const [search, setSearch] = useState("")
  const [page, setPage] = useState(1)
  const [filter, setFilter] = useState("")
  const [preview, setPreview] = useState<Media | null>(null)
  const [params, setParams] = useSearchParams()
  const uploadOpen = params.get("upload") === "1"
  const uploadDialog = useRef<HTMLDialogElement>(null)
  function showUpload(open: boolean) {
    setParams(previous => { const next = new URLSearchParams(previous); if (open) next.set("upload", "1"); else next.delete("upload"); return next }, { replace: !open })
  }
  useEffect(() => {
    if (uploadOpen && !uploadDialog.current?.open) uploadDialog.current?.showModal()
    else if (!uploadOpen && uploadDialog.current?.open) uploadDialog.current.close()
  }, [uploadOpen])
  useEffect(() => { const timer = window.setTimeout(() => { setSearch(q); setPage(1) }, 300); return () => window.clearTimeout(timer) }, [q])
  const [editing, setEditing] = useState<string | null>(null)
  const [draft, setDraft] = useState("")
  const media = useQuery({
    queryKey: ["media", search, page, filter],
    refetchInterval: query => query.state.data?.items.some(item => ["pending", "queued", "probing", "processing", "uploading"].includes(item.status)) ? 4000 : false,
    queryFn: () => api<{ items: Media[]; total: number; per_page: number }>(`/api/v1/media?q=${encodeURIComponent(search)}&page=${page}&status=${filter}`),
    enabled: Boolean(session.data?.user),
  })
  const userId = session.data?.user?.id
  async function save(item: Media) {
    try {
      await api(`/api/v1/media/${item.id}`, { method: "PATCH", body: JSON.stringify({ title: draft }) })
      setEditing(null)
      await client.invalidateQueries({ queryKey: ["media"] })
    } catch (error) {
      push(error instanceof Error ? error.message : "Gagal menyimpan film")
    }
  }
  async function remove(item: Media) {
    if (!window.confirm(`Hapus film ${item.title}?`)) return
    try {
      await api(`/api/v1/media/${item.id}`, { method: "DELETE" })
      await client.invalidateQueries({ queryKey: ["media"] })
    } catch (error) {
      push(error instanceof Error ? error.message : "Gagal menghapus film")
    }
  }
  return (
    <Shell>
      <div className="mb-6 flex flex-wrap items-center justify-between gap-4">
        <h1 className="font-display text-4xl">Pustaka</h1>
        <div className="flex flex-wrap items-center gap-3">
          <label className="field"><span>Cari judul</span><input placeholder="Cari judul" value={q} onChange={(event) => setQ(event.target.value)} /></label>
          <select aria-label="Filter status film" className="rounded-xl border p-2" value={filter} onChange={(event) => { setFilter(event.target.value); setPage(1) }}><option value="">Semua status</option><option value="ready">Siap ditonton</option><option value="processing">Sedang diolah</option><option value="failed">Gagal</option></select>
          <Button onClick={() => showUpload(true)}>Tambah film</Button>
        </div>
      </div>
      {!session.data?.user ? <p className="text-mist">Masuk dulu untuk melihat dan mengelola film.</p> : null}
      {media.error instanceof Error ? <p className="mb-4 text-sm text-amber">{media.error.message}</p> : null}
      {media.isLoading ? <p className="py-8 text-mist">Memuat pustaka film…</p> : null}
      {media.data?.items.length === 0 ? <Panel title="Belum ada film yang cocok"><p className="text-sm text-mist">Ubah pencarian, atau gunakan Tambah film untuk mengisi pustaka.</p></Panel> : null}
      <div className="library-grid">
        {(media.data?.items || []).map((item) => {
          const mine = item.owner_id === userId || session.data?.user?.role === "admin"
          return (
            <article key={item.id} className="media-card">
              <p className="media-format">{item.provider === "youtube" ? "Player YouTube" : "Video unggahan"}</p>
              <div>
                {editing === item.id ? (
                  <Field label="Judul film" value={draft} onChange={(event) => setDraft(event.target.value)} />
                ) : (
                  <h2 className="font-display text-2xl">{item.title}</h2>
                )}
                <p className="media-meta">{({ pending: "Unggahan belum selesai", ready: "Siap ditonton", processing: "Sedang diolah", probing: "Memeriksa video", queued: "Dalam antrean", uploading: "Sedang diunggah", failed: "Pengolahan gagal" } as Record<string, string>)[item.status] || item.status}{item.duration_ms ? ` · ${Math.floor(item.duration_ms / 60000)} menit` : ""}</p>
                <Button tone="ghost" className="mt-4" disabled={item.status !== "ready"} onClick={() => setPreview(item)}>Pratinjau</Button>
                {item.status !== "ready" ? <p className="form-note mt-2">Pratinjau tersedia setelah film selesai diolah.</p> : null}
                {mine ? (
                  <div className="media-actions">
                    {editing === item.id ? (
                      <Button onClick={() => save(item)}>Simpan</Button>
                    ) : (
                      <Button tone="ghost" onClick={() => { setEditing(item.id); setDraft(item.title) }}>Ubah</Button>
                    )}
                    <Button tone="ghost" onClick={() => remove(item)}>Hapus</Button>
                  </div>
                ) : null}
              </div>
            </article>
          )
        })}
      </div>
      {media.data && media.data.total > media.data.per_page ? <div className="mt-6 flex items-center justify-center gap-4"><Button tone="ghost" disabled={page <= 1} onClick={() => setPage(page - 1)}>← Sebelumnya</Button><span className="text-sm text-mist">{page} / {Math.ceil(media.data.total / media.data.per_page)}</span><Button tone="ghost" disabled={page * media.data.per_page >= media.data.total} onClick={() => setPage(page + 1)}>Berikutnya →</Button></div> : null}
      <dialog ref={uploadDialog} className="media-dialog" aria-labelledby="upload-title" onClose={() => { if (uploadOpen) showUpload(false) }}><header className="modal-heading"><div><h2 id="upload-title">Tambah film</h2><p>Film akan masuk ke pustaka Anda.</p></div><button className="secondary-button" onClick={() => showUpload(false)}>Tutup</button></header>{uploadOpen ? <UploadForm /> : null}</dialog>
      {preview ? <Suspense fallback={<p role="status">Menyiapkan pratinjau…</p>}><MediaPreview media={preview} onClose={() => setPreview(null)} /></Suspense> : null}
    </Shell>
  )
}

function UploadForm() {
  const push = useToasts((state) => state.push)
  const client = useQueryClient()
  const session = useSession()
  const [title, setTitle] = useState("")
  const [file, setFile] = useState<File | null>(null)
  const [fileKey, setFileKey] = useState(0)
  const [busy, setBusy] = useState(false)
  const [loaded, setLoaded] = useState(0)
  const uploadAbortRef = useRef<AbortController | null>(null)
  const uploadSessionRef = useRef<string | null>(null)
  const [resumeHint, setResumeHint] = useState(false)
  const [source, setSource] = useState("file")
  const resumeKey = `nobarsync-upload:${session.data?.user?.id || "anonymous"}`
  useEffect(() => { setResumeHint(Boolean(localStorage.getItem(resumeKey))) }, [resumeKey])
  useEffect(() => () => uploadAbortRef.current?.abort(), [])
  async function upload(chosen: File) {
    type Resume = { id: string; partSize: number; fingerprint: string; parts: { part_number: number; etag: string }[] }
    const fingerprint = `${chosen.name}:${chosen.size}:${chosen.lastModified}`
    const controller = new AbortController()
    uploadAbortRef.current = controller
    let saved: Resume | null = null
    try { saved = JSON.parse(localStorage.getItem(resumeKey) || "null") as Resume | null } catch { localStorage.removeItem(resumeKey) }
    if (saved && saved.fingerprint !== fingerprint) throw new Error("Ada unggahan tertunda. Pilih berkas yang sama atau batalkan unggahan lama.")
    if (!saved) {
      const created = await api<{ upload_session_id: string; part_size: number }>("/api/v1/media/uploads", {
        method: "POST", signal: controller.signal,
        body: JSON.stringify({ title, content_type: chosen.type || "application/octet-stream", byte_size: chosen.size }),
      })
      saved = { id: created.upload_session_id, partSize: created.part_size, fingerprint, parts: [] }
      localStorage.setItem(resumeKey, JSON.stringify(saved))
    }
    uploadSessionRef.current = saved.id
    setResumeHint(true)
    for (let offset = 0, number = 1; offset < chosen.size; number++) {
      if (controller.signal.aborted) throw new Error("Unggahan dijeda. Pilih berkas yang sama untuk melanjutkan.")
      const chunk = chosen.slice(offset, offset + saved.partSize)
      if (!saved.parts.some((part) => part.part_number === number)) {
        const signed = await api<{ url: string }>(`/api/v1/media/uploads/${saved.id}/parts`, { method: "POST", signal: controller.signal, body: JSON.stringify({ part_number: number }) })
        let etag = ""
        for (let attempt = 0; attempt < 3; attempt++) {
          try { etag = await putPart(signed.url, chunk, (sent) => setLoaded(offset + sent), controller.signal); break }
          catch (error) { if (controller.signal.aborted || attempt === 2) throw error }
        }
        saved.parts.push({ part_number: number, etag })
        localStorage.setItem(resumeKey, JSON.stringify(saved))
      }
      offset += chunk.size
      setLoaded(offset)
    }
    await api(`/api/v1/media/uploads/${saved.id}/complete`, { method: "POST", signal: controller.signal, body: JSON.stringify({ parts: saved.parts.sort((a, b) => a.part_number - b.part_number) }) })
    localStorage.removeItem(resumeKey)
    setResumeHint(false)
    uploadSessionRef.current = null
    await client.invalidateQueries({ queryKey: ["media"] })
    push("Unggahan selesai. Film sedang diolah untuk pemutaran adaptif.")
  }
  async function abortUpload() {
    uploadAbortRef.current?.abort()
    let id = uploadSessionRef.current
    try { id ||= (JSON.parse(localStorage.getItem(resumeKey) || "null") as { id?: string } | null)?.id || null } catch { /* Invalid local state is discarded. */ }
    if (id) await api(`/api/v1/media/uploads/${id}/abort`, { method: "POST" })
    localStorage.removeItem(resumeKey); setResumeHint(false); setLoaded(0)
    await client.invalidateQueries({ queryKey: ["media"] })
  }
  return (
    <div className="upload-form">
      <fieldset className="source-picker"><legend>Sumber film</legend>{[{id:"file",label:"Berkas video"},{id:"youtube",label:"YouTube"},{id:"url",label:"URL langsung"}].map(item => <label key={item.id}><input type="radio" name="upload-source" checked={source===item.id} disabled={busy} onChange={() => setSource(item.id)} />{item.label}</label>)}</fieldset>
      <Field label={source === "file" ? "Judul" : "Judul (opsional)"} value={title} onChange={event => setTitle(event.target.value)} />
      {source === "file" ? <form className="space-y-3 mt-5" onSubmit={(event) => {
          event.preventDefault()
          if (!title.trim() || !file) {
            push("Isi judul dan pilih berkas dulu.")
            return
          }
          setBusy(true)
          upload(file)
            .then(() => {
              setFile(null)
              setTitle("")
              setFileKey((value) => value + 1)
              setLoaded(0)
            })
            .catch((error: Error) => push(error.message))
            .finally(() => setBusy(false))
        }}>
          {resumeHint ? <p className="rounded-xl border border-amber/30 bg-amber/10 p-3 text-sm">Unggahan tertunda tersimpan. Pilih berkas yang sama untuk melanjutkan bagian yang belum terkirim.</p> : null}
          <label className="button button-ghost">
            Pilih berkas
            <input key={fileKey} className="sr-only" type="file" accept="video/mp4,video/webm,video/quicktime,.mkv" onChange={(event) => setFile(event.target.files?.[0] || null)} />
          </label>
          <p className="text-sm text-mist">{file ? `${file.name} · ${formatBytes(file.size)}` : "Belum ada berkas dipilih."}</p>
          <Button type="submit" disabled={busy || !title.trim() || !file}>{busy ? "Mengunggah..." : resumeHint ? "Lanjutkan unggahan" : "Unggah film"}</Button>
          {busy ? <Button type="button" tone="ghost" onClick={() => uploadAbortRef.current?.abort()}>Jeda unggahan</Button> : null}
          {resumeHint && !busy ? <Button type="button" tone="danger" onClick={() => void abortUpload().catch((error: Error) => push(error.message))}>Batalkan unggahan</Button> : null}
          {busy && file ? (
            <div>
              <div className="h-2 overflow-hidden rounded-full bg-stone-200">
                <div className="h-full bg-amber transition-[width]" style={{ width: `${Math.min(100, Math.round((loaded / file.size) * 100))}%` }} />
              </div>
              <p className="mt-2 text-sm text-mist">{Math.min(100, Math.round((loaded / file.size) * 100))}% · {formatBytes(loaded)} dari {formatBytes(file.size)}</p>
            </div>
          ) : <p className="text-sm text-mist">Berkas dikirim langsung ke penyimpanan. Film besar menampilkan progres per bagian.</p>}
          <p className="form-note">Menutup modal menjeda unggahan. Pilih berkas yang sama untuk melanjutkan nanti.</p>
        </form> : source === "youtube" ? <form className="mt-5 space-y-3" onSubmit={(event) => {
          event.preventDefault()
          const url = String(new FormData(event.currentTarget).get("url") || "").trim()
          if (!url) {
            push("Tempel URL YouTube dulu.")
            return
          }
          void api("/api/v1/media/youtube", { method: "POST", body: JSON.stringify({ url, title }) })
            .then(() => {
              push("Video YouTube ditambahkan. Sinkronnya terbatas oleh player resmi.")
              return client.invalidateQueries({ queryKey: ["media"] })
            })
            .catch((error: Error) => push(error.message))
        }}>
          <Field label="URL YouTube" name="url" placeholder="https://www.youtube.com/watch?v=..." />
          <Button type="submit">Tambahkan YouTube</Button>
        </form> : <form className="mt-5 space-y-3" onSubmit={(event) => { event.preventDefault(); const url = String(new FormData(event.currentTarget).get("source_url") || "").trim(); if (!url) return; void api("/api/v1/media/import-url", { method: "POST", body: JSON.stringify({ url, title: title || "Impor video" }) }).then(() => { push("Impor masuk antrean pengolahan"); void client.invalidateQueries({ queryKey: ["media"] }) }).catch((error: Error) => push(error.message)) }}><Field label="URL video langsung" name="source_url" type="url" required placeholder="https://domain-diizinkan/video.mp4" /><p className="form-note">Gunakan domain yang diizinkan pengelola. Untuk YouTube, pilih sumber YouTube.</p><Button type="submit">Impor video</Button></form>}
    </div>
  )
}

export function CreateRoom() {
  const navigate = useNavigate()
  const push = useToasts((state) => state.push)
  const [title, setTitle] = useState("Manonton malam ini")
  const [visibility, setVisibility] = useState("public")
  const [mediaId, setMediaId] = useState("")
  const media = useQuery({
    queryKey: ["media", "create"],
    queryFn: () => api<{ items: Media[] }>("/api/v1/media"),
  })
  const films = media.data?.items || []
  const create = useMutation({
    mutationFn: () => api<{ room: Room }>("/api/v1/rooms", { method: "POST", body: JSON.stringify({ title, visibility, media_id: mediaId }) }),
    onSuccess: (data) => navigate(`/rooms/${data.room.code}`),
    onError: (error: Error) => push(error.message),
  })
  return (
    <Shell>
      <div className="page-heading"><div><h1>Buat ruang</h1><p>Pilih film dan tentukan siapa yang bisa bergabung.</p></div></div><Panel className="max-w-xl">
        <form className="space-y-3" onSubmit={(event) => {
          event.preventDefault()
          if (!mediaId) {
            push("Pilih satu film.")
            return
          }
          create.mutate()
        }}>
          <Field label="Judul" value={title} onChange={(event) => setTitle(event.target.value)} />
          <label className="block text-sm text-mist">Film
            <select className="mt-1 w-full" value={mediaId} onChange={(event) => setMediaId(event.target.value)}>
              <option value="">Pilih satu film</option>
              {films.map((item) => <option key={item.id} value={item.id}>{item.title}</option>)}
            </select>
          </label>
          <label className="block text-sm text-mist">Visibilitas
            <select className="mt-1 w-full" value={visibility} onChange={(event) => setVisibility(event.target.value)}>
              <option value="public">Publik</option>
              <option value="private">Privat</option>
              <option value="password">Kata sandi</option>
            </select>
          </label>
          <Button type="submit" disabled={create.isPending || !mediaId}>Buat</Button>
          {films.length === 0 ? <p className="text-sm text-mist">Belum ada film. Tambah dulu dari Pustaka, lalu kembali ke sini.</p> : null}
        </form>
      </Panel>
    </Shell>
  )
}

export function Join() {
  const navigate = useNavigate()
  const push = useToasts((state) => state.push)
  const [code, setCode] = useState("")
  async function submit() {
    try {
      const joined = await api<{ member: { role: string } }>(`/api/v1/rooms/${code.toUpperCase()}/join`, { method: "POST", body: JSON.stringify({}) })
      navigate(joined.member.role === "viewer" ? `/watch/${code.toUpperCase()}` : `/rooms/${code.toUpperCase()}`)
    } catch (error) {
      push(error instanceof Error ? error.message : "Gagal gabung")
    }
  }
  return (
    <Shell>
      <div className="page-heading"><div><h1>Gabung ruang</h1><p>Masukkan kode dari teman untuk bergabung dengan akun Anda.</p></div></div><Panel className="max-w-md">
        <form className="space-y-3" onSubmit={(event) => { event.preventDefault(); void submit() }}>
          <Field label="Kode" value={code} onChange={(event) => setCode(event.target.value)} />
          <p className="text-sm text-mist">Anda bergabung menggunakan akun yang sedang login.</p>
          <Button type="submit">Masuk ruang</Button>
        </form>
      </Panel>
    </Shell>
  )
}

export function QuickJoin() {
  const { code = "" } = useParams()
  const navigate = useNavigate()
  const push = useToasts((state) => state.push)
  useEffect(() => {
    let cancelled = false
    const roomCode = code.toUpperCase()
    async function enter() {
      await api(`/api/v1/rooms/${roomCode}/join`, { method: "POST", body: JSON.stringify({}) })
      if (!cancelled) navigate(`/watch/${roomCode}`, { replace: true })
    }
    queueMicrotask(() => {
      if (cancelled) return
      void enter().catch((error: Error) => {
        if (cancelled) return
        push(error.message)
        navigate("/join")
      })
    })
    return () => { cancelled = true }
  }, [code, navigate, push])
  return <Shell><p>Menggabungkan ke ruang...</p></Shell>
}

export function Lobby() {
  const { code = "" } = useParams()
  const navigate = useNavigate()
  const session = useSession()
  const client = useQueryClient()
  const push = useToasts((state) => state.push)
  const room = useQuery({
    queryKey: ["room", code],
    queryFn: () => api<{ room: Room; members: Member[] }>(`/api/v1/rooms/${code}`),
  })
  const media = useQuery({
    queryKey: ["media", "lobby"],
    queryFn: () => api<{ items: Media[] }>("/api/v1/media"),
    enabled: Boolean(session.data?.user),
  })
  if (room.error instanceof Error) return <Shell><p>{room.error.message}</p></Shell>
  if (!room.data) return <Shell><p>Memuat ruang...</p></Shell>
  const mine = room.data.members.find((member) => member.user_id && member.user_id === session.data?.user?.id)
  const host = mine?.role === "host" || session.data?.user?.role === "admin"
  async function run(path: string, method: string, body?: object) {
    try {
      await api(path, { method, body: body ? JSON.stringify(body) : undefined })
      await client.invalidateQueries({ queryKey: ["room", code] })
      return true
    } catch (error) {
      push(error instanceof Error ? error.message : "Gagal")
      return false
    }
  }
  return (
    <Shell>
      <div className="page-heading"><div><h1>{room.data.room.title}</h1><p>Kode ruang: {room.data.room.code}</p></div></div><Panel title="Pengaturan ruang">
        <p className="text-sm text-mist">{host ? "Bagikan kode ini, tunggu teman, lalu masuk." : "Tekan Masuk untuk ikut nonton."}</p>
        <p className="mt-1 font-display text-4xl tracking-[0.25em] text-amber">{room.data.room.code}</p>
        <p className="mt-1 text-sm text-mist">{room.data.room.status === "open" ? "Terbuka" : "Ditutup"} · {room.data.room.locked ? "dikunci" : "terbuka untuk anggota"}</p>
        <p className="mt-2 text-sm">Film: {(media.data?.items || []).find((item) => item.id === room.data?.room.media_id)?.title || (room.data.room.media_id ? "sudah dipasang" : "belum dipilih")}</p>
        <ul className="my-4 space-y-2">
          {room.data.members.map((member) => (
            <li key={member.id} className="flex items-center justify-between gap-3">
              <span>{member.display_name} · {member.role}</span>
              {host && member.role !== "host" ? (
                <Button tone="ghost" onClick={() => run(`/api/v1/rooms/${code}/kick`, "POST", { member_id: member.id })}>Keluarkan</Button>
              ) : null}
            </li>
          ))}
        </ul>
        <div className="flex flex-wrap gap-2">
          {room.data.room.status === "open" ? <Link className="button button-primary" to={`/watch/${room.data.room.code}`}>Masuk pemutar</Link> : null}
          <Button tone="ghost" onClick={() => run(`/api/v1/rooms/${code}/leave`, "POST", {}).then((ok) => { if (ok) navigate("/dashboard") })}>Keluar</Button>
        </div>
        {host ? <div className="mt-6 grid gap-5 border-t border-line pt-6 md:grid-cols-2"><div><h3 className="mb-3 text-lg font-semibold">Program malam ini</h3><p className="mb-3 text-xs text-mist">Pilih film yang sudah siap, atau susun antrean untuk ditonton berikutnya.</p><div className="max-h-72 space-y-2 overflow-auto">{(media.data?.items || []).map((item) => <div className="flex items-center gap-2 rounded-xl border border-line p-3" key={item.id}><div className="min-w-0 flex-1"><strong className="block truncate text-sm">{item.title}</strong><small className="text-mist">{item.status}</small></div><Button tone="ghost" disabled={item.status !== "ready"} onClick={() => run(`/api/v1/rooms/${code}/media`, "POST", { media_id: item.id })}>Pilih</Button><Button tone="ghost" disabled={item.status !== "ready"} onClick={() => run(`/api/v1/rooms/${code}/playlist`, "POST", { media_id: item.id }).then((ok) => { if (ok) push("Film ditambahkan ke antrean") })}>＋</Button></div>)}</div></div><form className="space-y-3" onSubmit={(event) => { event.preventDefault(); const data = new FormData(event.currentTarget); void run(`/api/v1/rooms/${code}/settings`, "PATCH", { buffering_mode: data.get("buffering_mode"), chat_permission: data.get("chat_permission") }) }}><h3 className="text-lg font-semibold">Kenyamanan ruang</h3><label className="block text-sm">Jika penonton buffering<select name="buffering_mode" defaultValue={room.data.room.buffering_mode} className="mt-2 block w-full rounded-xl border p-3"><option value="independent">Tetap berjalan untuk penonton lain</option><option value="pause_all">Jeda saat banyak penonton buffering</option><option value="host_decides">Host menentukan</option></select></label><label className="block text-sm">Izin obrolan<select name="chat_permission" defaultValue={room.data.room.chat_permission} className="mt-2 block w-full rounded-xl border p-3"><option value="everyone">Semua peserta</option><option value="host_mod">Host dan moderator</option><option value="off">Nonaktif</option></select></label><Button type="submit">Simpan pengaturan</Button></form></div> : null}
        {host ? (
          <div className="mt-4 flex flex-wrap gap-2">
            <Button tone="ghost" onClick={() => run(`/api/v1/rooms/${code}/lock`, "POST", { locked: !room.data?.room.locked })}>
              {room.data.room.locked ? "Buka kunci" : "Kunci"}
            </Button>
            {room.data.room.status === "open" ? (
              <Button tone="ghost" onClick={() => {
                if (window.confirm("Tutup ruang ini?")) void run(`/api/v1/rooms/${code}/close`, "POST", {})
              }}>Tutup</Button>
            ) : null}
            <Button tone="ghost" onClick={() => {
              if (window.confirm("Hapus ruang ini beserta chat dan anggotanya?")) {
                void api(`/api/v1/rooms/${code}`, { method: "DELETE" })
                  .then(() => navigate("/dashboard"))
                  .catch((error: Error) => push(error.message))
              }
            }}>Hapus</Button>
          </div>
        ) : null}
      </Panel>
    </Shell>
  )
}

export function Profile() {
  const [name, setName] = useState("")
  const session = useSession()
  const client = useQueryClient()
  const navigate = useNavigate()
  const push = useToasts((state) => state.push)
  const [busy, setBusy] = useState(false)
  if (session.isLoading) return <Shell><p>Memuat profil…</p></Shell>
  if (!session.data?.user) return <Navigate to="/login" />
  return <Shell>
    <div className="page-heading"><div><h1>Akun Anda</h1><p>{session.data.user.email}</p></div></div>
    <div className="grid gap-6 md:grid-cols-2">
      <Panel title="Profil penonton">
        <form className="space-y-4" onSubmit={event => {
          event.preventDefault(); setBusy(true)
          void api("/api/v1/auth/me", { method: "PATCH", body: JSON.stringify({ display_name: name || session.data?.user?.display_name }) })
            .then(() => { push("Profil diperbarui"); return client.invalidateQueries({ queryKey: ["me"] }) })
            .catch((error: Error) => push(error.message)).finally(() => setBusy(false))
        }}>
          <Field label="Nama tampilan" minLength={2} maxLength={40} placeholder={session.data.user.display_name} value={name} onChange={event => setName(event.target.value)} />
          <Button type="submit" disabled={busy}>Simpan profil</Button>
        </form>
        <form className="mt-6 space-y-3 border-t border-line pt-5" onSubmit={event => {
          event.preventDefault(); const data = new FormData(event.currentTarget); setBusy(true)
          void api("/api/v1/auth/avatar", { method: "POST", body: data }).then(() => push("Avatar diperbarui")).catch((error: Error) => push(error.message)).finally(() => setBusy(false))
        }}>
          <label className="field"><span>Avatar (JPG, PNG, WebP, maksimal 1 MB)</span><input name="file" type="file" accept="image/jpeg,image/png,image/webp" required /></label>
          <Button type="submit" tone="ghost" disabled={busy}>Unggah avatar</Button>
        </form>
      </Panel>
      <Panel title="Keamanan akun">
        <form className="space-y-4" onSubmit={event => {
          event.preventDefault(); const form = event.currentTarget; const data = new FormData(form)
          if (data.get("new_password") !== data.get("confirmation")) { push("Konfirmasi kata sandi tidak cocok"); return }
          setBusy(true)
          void api("/api/v1/auth/password", { method: "POST", body: JSON.stringify({ old_password: data.get("old_password"), new_password: data.get("new_password") }) })
            .then(() => { push("Kata sandi diperbarui"); form.reset() }).catch((error: Error) => push(error.message)).finally(() => setBusy(false))
        }}>
          <Field label="Kata sandi lama" type="password" name="old_password" autoComplete="current-password" required />
          <Field label="Kata sandi baru" type="password" name="new_password" autoComplete="new-password" minLength={8} maxLength={72} required />
          <Field label="Konfirmasi kata sandi baru" type="password" name="confirmation" autoComplete="new-password" required />
          <Button type="submit" disabled={busy}>Ubah kata sandi</Button>
        </form>
        <Button tone="danger" className="mt-6" onClick={() => void api("/api/v1/auth/logout", { method: "POST" }).then(() => { client.clear(); navigate("/login") }).catch((error: Error) => push(error.message))}>Keluar dari akun</Button>
      </Panel>
    </div>
  </Shell>
}

function putPart(url: string, body: Blob, onProgress: (loaded: number) => void, signal?: AbortSignal) {
  return new Promise<string>((resolve, reject) => {
    const xhr = new XMLHttpRequest()
    xhr.open("PUT", url)
    xhr.timeout = 180_000
    const onAbort = () => xhr.abort()
    signal?.addEventListener("abort", onAbort, { once: true })
    xhr.onloadend = () => signal?.removeEventListener("abort", onAbort)
    xhr.onabort = () => reject(new Error("Unggahan dijeda. Lanjutkan dengan berkas yang sama."))
    xhr.ontimeout = () => reject(new Error("Waktu unggah bagian habis"))
    if (signal?.aborted) { reject(new Error("Unggahan dijeda")); return }
    xhr.upload.onprogress = (event) => {
      if (event.lengthComputable) onProgress(event.loaded)
    }
    xhr.onload = () => {
      const etag = xhr.getResponseHeader("etag")
      if (xhr.status >= 200 && xhr.status < 300 && etag) resolve(etag)
      else reject(new Error("Bagian unggahan gagal"))
    }
    xhr.onerror = () => reject(new Error("Bagian unggahan gagal"))
    xhr.send(body)
  })
}

function formatBytes(value: number) {
  if (value < 1024) return `${value} B`
  const units = ["KB", "MB", "GB", "TB"]
  let size = value / 1024
  let index = 0
  while (size >= 1024 && index < units.length - 1) {
    size /= 1024
    index += 1
  }
  return `${size.toFixed(size >= 10 ? 0 : 1)} ${units[index]}`
}

export function Admin() {
  const session = useSession()
  const enabled = session.data?.user?.role === "admin"
  if (session.isLoading) return <Shell><p>Memuat…</p></Shell>
  if (!enabled) return <Navigate to="/dashboard" />
  return <Shell>{session.data?.user ? <AdminConsole me={session.data.user.id} /> : null}</Shell>
}
