import { useQuery } from "@tanstack/react-query"
import { api } from "./api"
import { Panel } from "./ui"
import { Button, Field } from "./ui"
import { useState } from "react"
import { Link } from "react-router"
import { useActivityUpdates } from "./activity"

type Person = { id: string; display_name: string; role: string; email?: string | null; room_code: string; room_title: string }
type OnlineUser = { id: string; display_name: string; email: string; role: string; tabs: number; pages: string[] }
type LiveRoom = {
  id: string
  code: string
  title: string
  locked: boolean
  online: boolean
  people: { id: string; display_name: string; role: string; email?: string | null }[]
  media_title: string | null
  playback: { status: string; position_ms: number; duration_ms: number }
}

function roleLabel(role: string) {
  if (role === "host") return "Host"
  if (role === "moderator") return "Moderator"
  return "Penonton"
}

function clock(ms: number) {
  const total = Math.max(0, Math.floor(ms / 1000))
  const hours = Math.floor(total / 3600)
  const minutes = Math.floor((total % 3600) / 60)
  const seconds = total % 60
  const tail = `${String(minutes).padStart(2, "0")}:${String(seconds).padStart(2, "0")}`
  return hours > 0 ? `${hours}:${tail}` : tail
}

function playLabel(status: string) {
  if (status === "playing") return "Diputar"
  if (status === "paused") return "Dijeda"
  if (status === "ended") return "Selesai"
  return "Belum mulai"
}

function positionCopy(play: LiveRoom["playback"]) {
  if (play.status === "idle" && play.position_ms === 0) return "Belum mulai"
  const at = clock(play.position_ms)
  const length = play.duration_ms > 0 ? ` dari ${clock(play.duration_ms)}` : ""
  return `${playLabel(play.status)} · ${at}${length}`
}

export function AdminLive() {
  useActivityUpdates("observe:admin", ["admin", "live"])
  const [search, setSearch] = useState("")
  const [onlyOnline, setOnlyOnline] = useState(false)
  const live = useQuery({
    queryKey: ["admin", "live"],
    queryFn: () => api<{ people: Person[]; users: OnlineUser[]; rooms: LiveRoom[]; rooms_total: number; sampled_at_ms: number }>("/api/v1/admin/live"),
    refetchInterval: 4000,
    refetchIntervalInBackground: false,
  })
  if (live.isPending) return <p role="status">Memuat ruang yang sedang hidup…</p>
  if (live.error instanceof Error) return <p role="alert">Daftar langsung gagal dimuat: {live.error.message}</p>
  const people = live.data?.people || []
  const rooms = live.data?.rooms || []
  const users = live.data?.users || []
  const onlineRooms = rooms.filter((room) => room.online).length
  const q = search.trim().toLowerCase()
  const visibleRooms = rooms.filter(room => (!onlyOnline || room.online) && `${room.title} ${room.code} ${room.media_title || ""} ${room.people.map(person => person.display_name).join(" ")}`.toLowerCase().includes(q))
  return <>
    <div className="panel-heading"><p role="status">{users.length} akun online · {new Set(people.map(person => person.id)).size} peserta di {onlineRooms} ruang. Kehadiran mengikuti koneksi aplikasi; posisi pemutaran diperbarui setiap 4 detik.</p><Button tone="ghost" disabled={live.isFetching} onClick={() => void live.refetch()}>Perbarui</Button></div>
    <Panel title="Akun online" subtitle="Akun dengan koneksi aplikasi aktif, termasuk yang sedang di Pustaka atau halaman lain. Beberapa tab dihitung sebagai satu akun.">
      {users.length === 0 ? <p className="empty-message">Belum ada akun yang terhubung.</p> : <ul>{users.map(user => <li className="live-person" key={user.id}>
        <span><strong>{user.display_name}</strong><small className="block">{user.email} · {user.role === "admin" ? "Admin" : "Pengguna"} · {user.tabs} tab</small></span>
        <small>{user.pages.map(page => page.startsWith("/watch/") ? `Menonton ${page.split("/").pop()}` : page.startsWith("/rooms/") ? `Detail ruang ${page.split("/").pop()}` : ({ "/": "Beranda", "/dashboard": "Ruang saya", "/library": "Pustaka", "/profile": "Akun", "/admin": "Administrasi", "/join": "Gabung ruang" } as Record<string,string>)[page] || page).join(", ")}</small>
      </li>)}</ul>}
    </Panel>
    <div className="mt-5">
    <Panel title="Orang yang sedang menonton" subtitle="Nama yang tampil adalah orang yang terhubung ke pemutar, bukan yang pernah masuk lalu keluar.">
      {people.length === 0 ? <p className="empty-message">Tidak ada yang sedang di pemutar.</p> : (
        <ul>
          {people.map((person) => (
            <li className="live-person" key={`${person.room_code}-${person.id}`}>
              <span>{person.display_name} <small>{roleLabel(person.role)}{person.email ? ` · ${person.email}` : ""}</small></span>
              <small>{person.room_title} · {person.room_code}</small>
            </li>
          ))}
        </ul>
      )}
    </Panel>
    </div>
    <div className="flex flex-wrap items-end gap-4 mt-6"><Field label="Cari ruang, film, atau peserta" value={search} onChange={event => setSearch(event.target.value)} /><label className="flex items-center gap-2 pb-3"><input type="checkbox" checked={onlyOnline} onChange={event => setOnlyOnline(event.target.checked)} />Hanya ruang berpenghuni</label></div>
    <div className="live-rooms">
      {visibleRooms.map((room) => (
        <Panel key={room.id} title={room.title} subtitle={`${room.code} · ${room.online ? `${room.people.length} orang` : "Kosong"}${room.locked ? " · dikunci" : ""}`}>
          <div className="live-room">
            <p>Film: {room.media_title || "Belum dipilih"}</p>
            <p>{positionCopy(room.playback)}</p>
            <Link className="button button-ghost mt-3" to={`/rooms/${room.code}`}>Lihat detail ruang</Link>
            {room.people.length ? (
              <ul>
                {room.people.map((person) => (
                  <li className="live-person" key={person.id}>
                    <span>{person.display_name}</span>
                    <small>{roleLabel(person.role)}{person.email ? ` · ${person.email}` : ""}</small>
                  </li>
                ))}
              </ul>
            ) : <p>Belum ada yang masuk pemutar.</p>}
          </div>
        </Panel>
      ))}
    </div>
    {(live.data?.rooms_total || 0) > rooms.length ? <p className="form-note mt-4">Menampilkan {rooms.length} ruang terbuka terbaru dari {live.data?.rooms_total}. Jumlah peserta di atas mengikuti ruang yang ditampilkan.</p> : null}
    {rooms.length === 0 ? <p className="empty-message">Belum ada ruang terbuka.</p> : null}
    {rooms.length > 0 && visibleRooms.length === 0 ? <p className="empty-message">Tidak ada ruang yang cocok dengan filter.</p> : null}
  </>
}
