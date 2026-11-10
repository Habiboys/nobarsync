import { VoiceCall } from "./VoiceCall"
import { Brand } from "./Brand"
import { ThemeToggle } from "./ThemeToggle"
import Hls from "hls.js"
import { useEffect, useRef, useState, type CSSProperties } from "react"
import { createPortal } from "react-dom"
import { Channel, Socket } from "phoenix"
import { Link, useParams } from "react-router"
import { api, ApiError } from "./api"
import type { Media } from "./api"
import { correctDrift, estimateOffset, targetPosition } from "./sync"
import type { ClockSample, Snapshot } from "./sync"
import { Badge, Button } from "./ui"

type Playback = { media_id: string; title: string; token: string; expires_at?: number; poster_key?: string; playback: { kind: string; manifest_key?: string; youtube_id?: string }; subtitles: { language: string; label: string; vtt_key: string }[] }
type Person = { id: string; display_name: string; role: string }
type Metric = { member_id: string; lag_ms: number; buffering: boolean; paused: boolean; updated_at_ms: number }
type Telemetry = { host_buffering: boolean; host_paused: boolean; members: Metric[] }
type Message = { id: string; body: string; display_name: string; member_id?: string; inserted_at?: string }
type Playlist = { id: string; votes: number; media: { id: string; title: string; status: string } | null }

export function WatchRoom() {
  const { code = "" } = useParams()
  // A room change creates a fresh session, including clocks, timers and adapters.
  return <WatchSession key={code} code={code} />
}

function WatchSession({ code }: { code: string }) {
  const videoRef = useRef<HTMLVideoElement>(null)
  const frameRef = useRef<HTMLDivElement>(null)
  const ytNodeRef = useRef<HTMLDivElement>(null)
  const ytRef = useRef<YtPlayer | null>(null)
  const hlsRef = useRef<Hls | null>(null)
  const channelRef = useRef<Channel | null>(null)
  const reactionTimesRef = useRef<number[]>([])
  const stateRef = useRef<Snapshot | null>(null)
  const roleRef = useRef("viewer")
  const clockRef = useRef<number | null>(null)
  const mediaRef = useRef<string | null>(null)
  const memberRef = useRef("")
  const playbackRef = useRef<Playback | null>(null)
  const seekRef = useRef(0)
  const revisionRef = useRef(-1)
  const bufferingRef = useRef(false)
  const initialRef = useRef(true)
  const primingRef = useRef(false)
  const playInFlightRef = useRef(false)
  const playRequestRef = useRef(false)
  const lastSignalRef = useRef<boolean | null>(null)
  const stallTimerRef = useRef(0)
  const queueDialogRef = useRef<HTMLDialogElement>(null)
  const volumeRef = useRef(1)
  const filmMutedRef = useRef(false)
  const duckedRef = useRef(false)
  const applyFilmRef = useRef<() => void>(() => {})
  const applyRef = useRef<(snapshot: Snapshot) => void>(() => {})
  const tickRef = useRef<() => void>(() => {})
  const chatEndRef = useRef<HTMLDivElement>(null)
  const [snapshot, setSnapshot] = useState<Snapshot | null>(null)
  const [playback, setPlayback] = useState<Playback | null>(null)
  const [people, setPeople] = useState<Person[]>([])
  const [metrics, setMetrics] = useState<Telemetry | null>(null)
  const [role, setRole] = useState("viewer")
  const [status, setStatus] = useState("Menghubungkan ke ruang…")
  const [connected, setConnected] = useState(false)
  const [chat, setChat] = useState<Message[]>([])
  const [draft, setDraft] = useState("")
  const [sending, setSending] = useState(false)
  const [chatOpen, setChatOpen] = useState(true)
  const [muted, setMuted] = useState(false)
  const [volume, setVolume] = useState(1)
  const [blocked, setBlocked] = useState(false)
  const [loading, setLoading] = useState(true)
  const [levels, setLevels] = useState<{ index: number; label: string }[]>([])
  const [quality, setQuality] = useState(-1)
  const [subtitle, setSubtitle] = useState("")
  const [theater, setTheater] = useState(false)
  const [fullscreen, setFullscreen] = useState(false)
  const [controlsIdle, setControlsIdle] = useState(false)
  const [micOpen, setMicOpen] = useState(true)
  const [micSlot, setMicSlot] = useState<HTMLSpanElement | null>(null)
  const [position, setPosition] = useState(0)
  const [duration, setDuration] = useState(0)
  const [countdown, setCountdown] = useState(0)
  const [ready, setReady] = useState(false)
  const [readiness, setReadiness] = useState<Record<string, boolean>>({})
  const [reactions, setReactions] = useState<{ id: string; emoji: string; display_name: string; at: number; burst: boolean; dx: number; dy: number }[]>([])
  const [playlist, setPlaylist] = useState<Playlist[]>([])
  const [startPending, setStartPending] = useState(false)
  const [queueOpen, setQueueOpen] = useState(false)
  const [queueSearch, setQueueSearch] = useState("")
  const [queuePage, setQueuePage] = useState(1)
  const [queueFilms, setQueueFilms] = useState<Media[]>([])
  const [queueTotal, setQueueTotal] = useState(0)
  const [queueLoading, setQueueLoading] = useState(false)
  const [queueError, setQueueError] = useState("")
  const [addingFilm, setAddingFilm] = useState<string | null>(null)
  const [queueBusy, setQueueBusy] = useState(false)
  const [processing, setProcessing] = useState<{ status: string; progress: number; error?: string } | null>(null)
  const [roomTitle, setRoomTitle] = useState("Ruang nonton")
  const [chatPermission, setChatPermission] = useState("everyone")
  const [playerNode, setPlayerNode] = useState<HTMLDivElement | null>(null)
  const canControl = role === "host" || role === "moderator"
  const active = snapshot?.pending && (clockRef.current !== null && performance.now() + clockRef.current >= snapshot.effective_at_ms) ? snapshot.pending : snapshot?.state
  const playing = active?.status === "playing"
  const isYoutube = playback?.playback.kind === "youtube"

  function command(event: string, payload: object = {}) {
    const push = channelRef.current?.push(event, { v: 1, request_id: crypto.randomUUID(), ...payload })
    push?.receive("error", (error) => setStatus(`Perintah ditolak: ${String(error.message || error.code || "coba lagi")}`))
    push?.receive("timeout", () => setStatus("Koneksi lambat. Perintah belum dikonfirmasi."))
    return push
  }

  useEffect(() => {
    let stopped = false
    let socket: Socket | null = null
    let tokenTimer = 0
    let clockTimer = 0
    let socketTokenTimer = 0
    let clockSampling = false
    const abort = new AbortController()
    async function refreshClock(channel: Channel) {
      if (clockSampling) return
      clockSampling = true
      try {
        const offset = await sampleClock(channel)
        if (!stopped) { clockRef.current = offset; tickRef.current() }
      } catch { if (!stopped) setStatus("Menunggu pengukuran jam server…") }
      finally { clockSampling = false }
    }
    async function loadMedia(id: string) {
      window.clearTimeout(tokenTimer)
      try {
        const next = await api<Playback>("/api/v1/playback/token", { method: "POST", body: JSON.stringify({ room_code: code }), signal: abort.signal })
        if (stopped || mediaRef.current !== id || next.media_id !== id) return
        playbackRef.current = next
        setPlayback(next)
        setProcessing(null)
        tokenTimer = window.setTimeout(() => void loadMedia(id), next.expires_at ? Math.max(10_000, next.expires_at * 1000 - Date.now() - 120_000) : 3_600_000)
      } catch (error) {
        if (stopped || mediaRef.current !== id) return
        setStatus(error instanceof Error ? error.message : "Gagal memuat film")
        if (error instanceof ApiError && error.status === 409) {
          void api<{ status: string; progress: number; error?: string }>(`/api/v1/media/${id}/processing`, { signal: abort.signal }).then((item) => { if (!stopped) setProcessing(item) }).catch(() => {})
          tokenTimer = window.setTimeout(() => void loadMedia(id), 5000)
        }
      }
    }
    function apply(next: Snapshot) {
      if (stopped || !next?.state || (stateRef.current && next.revision < stateRef.current.revision)) return
      stateRef.current = next
      setSnapshot(next)
      if (next.media_id !== mediaRef.current) {
        videoRef.current?.pause()
        ytRef.current?.pauseVideo()
        mediaRef.current = next.media_id
        playbackRef.current = null
        setPlayback(null)
        setLoading(true)
        setSubtitle("")
        initialRef.current = true
        lastSignalRef.current = null
        if (next.media_id) void loadMedia(next.media_id)
        else { setLoading(false); setStatus("Host belum memilih film") }
      }
      tickRef.current()
    }
    applyRef.current = apply
    async function refreshPlaylist() {
      try { const data = await api<{ items: Playlist[] }>(`/api/v1/rooms/${code}/playlist`, { signal: abort.signal }); if (!stopped) setPlaylist(data.items) } catch { /* Room playback remains available. */ }
    }
    async function connect() {
      // Direct /watch links must join with the current account before opening channels.
      await api(`/api/v1/rooms/${code}/join`, { method: "POST", body: "{}", signal: abort.signal })
      if (stopped) return
      const [token, room] = await Promise.all([
        api<{ token: string }>("/api/v1/auth/socket-token", { method: "POST", signal: abort.signal }),
        api<{ room: { id: string; title: string; chat_permission: string } }>(`/api/v1/rooms/${code}`, { signal: abort.signal }),
      ])
      if (stopped) return
      setRoomTitle(room.room.title)
      setChatPermission(room.room.chat_permission)
      const initial = await api<{ snapshot: Snapshot }>(`/api/v1/rooms/${code}/playback`, { signal: abort.signal })
      if (stopped) return
      apply(initial.snapshot)
      let socketToken = token.token
      socketTokenTimer = window.setInterval(() => {
        void api<{ token: string }>("/api/v1/auth/socket-token", { method: "POST", signal: abort.signal }).then((data) => { socketToken = data.token }).catch(() => {})
      }, 60_000)
      socket = new Socket("/socket", { params: () => ({ token: socketToken }), timeout: 30000 })
      socket.onError(() => { if (!stopped) { setConnected(false); setStatus("Koneksi realtime gagal. Memuat ulang koneksi… Pastikan jaringan mengizinkan WebSocket.") } })
      socket.connect()
      const channel = socket.channel(`room:${room.room.id}`, { tab_id: crypto.randomUUID() })
      channelRef.current = channel
      channel.on("playback.state", (data) => apply(data as unknown as Snapshot))
      channel.on("playback.snapshot", (data) => apply(data as unknown as Snapshot))
      channel.on("room.telemetry", (data) => setMetrics(data as unknown as Telemetry))
      channel.on("room.presence", (data) => {
        const presence = data.presence as Record<string, { metas: { display_name: string; role: string }[] }>
        setPeople(Object.entries(presence).map(([id, item]) => ({ id, display_name: item.metas[0]?.display_name || "Penonton", role: item.metas[0]?.role || "viewer" })))
      })
      channel.on("chat.message", (data) => setChat((items) => [...items.filter((item) => item.id !== data.id), data as unknown as Message].slice(-100)))
      channel.on("reaction.broadcast", (data) => {
        const now = Date.now()
        const recent = reactionTimesRef.current.filter((time) => now - time < 900)
        recent.push(now)
        reactionTimesRef.current = recent
        const burst = recent.length >= 3
        const spread = burst ? 180 + Math.round(Math.random() * 240) : 24 + Math.round(Math.random() * 70)
        const angle = burst ? Math.random() * Math.PI * 2 : (Math.random() - 0.5)
        setReactions((items) => [...items.filter((item) => now - item.at < 2200).slice(-23), {
          id: crypto.randomUUID(),
          emoji: String(data.emoji),
          display_name: String(data.display_name || ""),
          at: now,
          burst,
          dx: Math.round(Math.cos(angle) * spread),
          dy: Math.round((burst ? Math.sin(angle) : -1) * spread),
        }])
      })
      channel.on("room.host_changed", () => { setStatus("Host berubah. Menyambungkan ulang…"); window.location.reload() })
      channel.on("room.closed", () => { videoRef.current?.pause(); ytRef.current?.pauseVideo(); window.location.assign("/dashboard") })
      channel.on("room.settings_changed", (data) => {
        if (data.ready) setReadiness(Object.fromEntries((data.ready as { member_id: string; ready: boolean }[]).map((item) => [item.member_id, item.ready])))
        if (data.playlist) void refreshPlaylist()
        const updated = data.room as { chat_permission?: string } | undefined
        if (updated?.chat_permission) setChatPermission(updated.chat_permission)
      })
      channel.on("room.error", (data) => {
        if (data.code === "kicked" && data.member_id === memberRef.current) { window.location.assign("/join"); return }
        setStatus(String(data.message || data.code))
      })
      channel.onError(() => { setConnected(false); clockRef.current = null; videoRef.current?.pause(); ytRef.current?.pauseVideo(); setStatus("Koneksi terputus. Menyambungkan kembali…") })
      channel.onClose(() => { if (!stopped) setConnected(false) })
      channel.join().receive("ok", (data) => {
        if (stopped) return
        const member = data.member as { id: string; role: string }
        memberRef.current = member.id
        roleRef.current = member.role
        setRole(member.role)
        const readyRows = (data.ready || []) as { member_id: string; ready: boolean }[]
        setReadiness(Object.fromEntries(readyRows.map((row) => [row.member_id, row.ready])))
        setReady(readyRows.some((row) => row.member_id === member.id && row.ready))
        setConnected(true)
        setStatus("Terhubung · mengikuti jam server")
        initialRef.current = true
        apply(data as unknown as Snapshot)
        void refreshClock(channel)
        void api<{ messages: Message[] }>(`/api/v1/rooms/${code}/messages`, { signal: abort.signal }).then((history) => {
          if (!stopped) setChat((items) => Array.from(new Map([...history.messages, ...items].map((item) => [item.id, item])).values()).slice(-100))
        }).catch(() => {})
        void refreshPlaylist()
      }).receive("error", (data) => { if (!stopped) { setConnected(false); setStatus(String(data.message || "Tidak dapat masuk ruang. Buka kembali tautan undangan.")) } })
        .receive("timeout", () => { if (!stopped) { setConnected(false); setStatus("Koneksi ruang melewati batas waktu. Menyambungkan ulang…") } })
      clockTimer = window.setInterval(() => void refreshClock(channel), 30_000)
    }
    const onVisible = () => {
      if (document.visibilityState === "visible" && channelRef.current) {
        void refreshClock(channelRef.current)
        void api<{ snapshot: Snapshot }>(`/api/v1/rooms/${code}/playback`, { signal: abort.signal }).then((data) => apply(data.snapshot)).catch(() => {})
      }
    }
    document.addEventListener("visibilitychange", onVisible)
    void connect().catch((error: Error) => { if (!stopped) setStatus(error.message) })
    return () => { stopped = true; abort.abort(); window.clearTimeout(tokenTimer); window.clearInterval(clockTimer); window.clearInterval(socketTokenTimer); document.removeEventListener("visibilitychange", onVisible); channelRef.current = null; socket?.disconnect() }
  }, [code])

  // Renew token in the existing adapter: changing credentials must not restart playback.
  useEffect(() => {
    playbackRef.current = playback
  }, [playback])

  useEffect(() => {
    const video = videoRef.current
    if (!video || Hls.isSupported() || playback?.playback.kind !== "hls" || !playback.playback.manifest_key) return
    const url = `/media/t/${playback.token}/${playback.playback.manifest_key}`
    if (!video.src || new URL(video.src).pathname === url) return
    const saved = video.currentTime * 1000
    const restore = () => {
      const current = stateRef.current
      const target = current && clockRef.current !== null ? targetPosition(current, performance.now() + clockRef.current) : saved
      video.currentTime = target / 1000
      tickRef.current()
    }
    video.addEventListener("loadedmetadata", restore, { once: true })
    video.src = url
    return () => video.removeEventListener("loadedmetadata", restore)
  }, [playback?.token, playback?.playback.kind, playback?.playback.manifest_key])

  useEffect(() => {
    const video = videoRef.current
    if (!video || playback?.playback.kind !== "hls" || !playback.playback.manifest_key) return
    initialRef.current = true
    const manifest = `/media/t/${playback.token}/${playback.playback.manifest_key}`
    if (Hls.isSupported()) {
      let recoveries = 0
      const hls = new Hls({ maxBufferLength: 20, maxMaxBufferLength: 40, backBufferLength: 15,
        xhrSetup: (xhr, url) => {
          const token = playbackRef.current?.token
          if (token && url.includes("/media/t/")) xhr.open("GET", url.replace(/\/media\/t\/[^/]+\//, `/media/t/${token}/`), true)
        },
      })
      hlsRef.current = hls
      hls.loadSource(manifest)
      hls.attachMedia(video)
      hls.on(Hls.Events.MANIFEST_PARSED, (_, data) => setLevels(data.levels.map((item, index) => ({ index, label: item.height ? `${item.height}p` : `Kualitas ${index + 1}` }))))
      hls.on(Hls.Events.ERROR, (_, data) => {
        if (!data.fatal) return
        if (recoveries++ < 3 && data.type === Hls.ErrorTypes.NETWORK_ERROR) hls.startLoad()
        else if (recoveries < 4 && data.type === Hls.ErrorTypes.MEDIA_ERROR) hls.recoverMediaError()
        else setStatus("Video gagal dimuat. Coba sinkronkan ulang atau pilih kualitas lebih rendah.")
      })
      return () => { hls.destroy(); hlsRef.current = null }
    }
    if (video.canPlayType("application/vnd.apple.mpegurl")) video.src = manifest
    else setStatus("Browser ini belum mendukung HLS")
    return () => { video.removeAttribute("src"); video.load() }
    // Token refresh is handled by xhrSetup; media identity controls adapter lifetime.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [playback?.media_id, playback?.playback.manifest_key])

  useEffect(() => {
    if (!isYoutube || !playback?.playback.youtube_id) return
    let stopped = false
    const id = playback.playback.youtube_id
    function create() {
      if (stopped || !window.YT || !ytNodeRef.current) return
      const node = document.createElement("div")
      ytNodeRef.current.replaceChildren(node)
      ytRef.current = new window.YT.Player(node, { videoId: id, playerVars: { controls: 0, disablekb: 1, playsinline: 1, rel: 0 }, events: {
        onReady: () => { bufferingRef.current = false; setLoading(false); applyFilmRef.current(); tickRef.current() },
        onStateChange: (event: { data: number }) => {
          bufferingRef.current = event.data === 3
          setLoading(event.data === 3)
          if (event.data === 1 || event.data === 2 || event.data === 3) signal(event.data === 3)
        },
        onError: () => setStatus("YouTube menolak pemutaran. Periksa izin embed video."),
      } })
    }
    if (window.YT?.Player) create()
    else {
      window.onYouTubeIframeAPIReady = create
      if (!document.querySelector('script[src="https://www.youtube.com/iframe_api"]')) {
        const script = document.createElement("script"); script.src = "https://www.youtube.com/iframe_api"; document.body.appendChild(script)
      }
    }
    return () => { stopped = true; ytRef.current?.destroy(); ytRef.current = null; window.onYouTubeIframeAPIReady = undefined }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isYoutube, playback?.playback.youtube_id])

  function localState() {
    const yt = ytRef.current
    const video = videoRef.current
    if (playbackRef.current?.playback.kind === "youtube") return yt ? { position: yt.getCurrentTime() * 1000, duration: yt.getDuration() * 1000, paused: yt.getPlayerState() !== 1, buffering: yt.getPlayerState() === 3, ready: yt.getDuration() > 0 } : null
    return video ? { position: video.currentTime * 1000, duration: Number.isFinite(video.duration) ? video.duration * 1000 : 0, paused: video.paused, buffering: bufferingRef.current || video.readyState < 3, ready: video.readyState >= 2 && !video.seeking } : null
  }
  function signal(buffering: boolean) {
    bufferingRef.current = buffering
    if (lastSignalRef.current === buffering) return
    lastSignalRef.current = buffering
    command(buffering ? "player.buffering" : "player.ready", { ready: !buffering, position_ms: Math.round(localState()?.position || 0) })
  }
  function seekLocal(ms: number) {
    if (!Number.isFinite(ms)) return
    if (playbackRef.current?.playback.kind === "youtube") ytRef.current?.seekTo(ms / 1000, true)
    else if (videoRef.current && videoRef.current.readyState >= 1) videoRef.current.currentTime = ms / 1000
    seekRef.current = performance.now()
  }
  function playLocal() {
    if (playbackRef.current?.playback.kind === "youtube") { ytRef.current?.playVideo(); return }
    const video = videoRef.current
    if (!video?.paused || playInFlightRef.current || blocked) return
    playInFlightRef.current = true
    void video.play().then(() => setBlocked(false)).catch((error: unknown) => {
      if (error instanceof DOMException && error.name === "AbortError") return
      if (error instanceof DOMException && error.name === "NotAllowedError") {
        setBlocked(true)
        if (roleRef.current === "host") signal(true)
      } else setStatus("Video belum dapat diputar. Tunggu buffer atau coba sinkronkan lagi.")
    }).finally(() => { playInFlightRef.current = false })
  }
  async function activatePlayer() {
    const video = videoRef.current
    if (!video || primingRef.current) return false
    if (playbackRef.current?.playback.kind === "youtube") { ytRef.current?.playVideo(); setBlocked(false); return true }
    primingRef.current = true
    try {
      // Await a successful gesture-driven play before pausing. An immediate pause
      // aborts play() and can leave autoplay locked when the countdown ends.
      await video.play()
      video.pause()
      setBlocked(false)
      signal(false)
      return true
    } catch (error) {
      if (error instanceof DOMException && error.name === "NotAllowedError") setBlocked(true)
      setStatus("Aktifkan player terlebih dahulu sebelum mulai bersama.")
      return false
    } finally { primingRef.current = false }
  }
  function reportWaiting() {
    setLoading(true)
    window.clearTimeout(stallTimerRef.current)
    stallTimerRef.current = window.setTimeout(() => {
      const video = videoRef.current
      const current = stateRef.current
      if (!video || !current || primingRef.current || video.seeking || video.readyState >= 3 || clockRef.current === null) return
      const next = current.pending && performance.now() + clockRef.current >= current.effective_at_ms ? current.pending : current.state
      if (next.status === "playing") signal(true)
    }, 600)
  }
  function pauseLocal() { videoRef.current?.pause(); ytRef.current?.pauseVideo() }
  function tick() {
    const current = stateRef.current
    const local = localState()
    if (!current || !local || clockRef.current === null || primingRef.current) return
    const now = performance.now()
    const serverNow = now + clockRef.current
    if (current.pending?.kind === "change_media" && serverNow < current.effective_at_ms) { pauseLocal(); return }
    const next = current.pending && serverNow >= current.effective_at_ms ? current.pending : current.state
    const target = targetPosition(current, serverNow)
    const fresh = revisionRef.current !== current.revision && (!current.pending || serverNow >= current.effective_at_ms)
    if (fresh || initialRef.current) {
      if (local.ready) {
        if (Math.abs(local.position - target) > 250) seekLocal(target)
        revisionRef.current = current.revision; initialRef.current = false
      }
    } else if (local.ready) {
      const decision = correctDrift({ driftMs: local.position - target, buffering: local.buffering, canSeek: true, lastSeekAt: seekRef.current, now, correcting: false })
      if (decision.type === "seek") seekLocal(target)
      if (videoRef.current) videoRef.current.playbackRate = decision.rate
      // YouTube only supports discrete rates; use bounded hard seeks there.
    }
    if (next.status !== "playing") pauseLocal()
    else if (local.ready) playLocal()
    setPosition(local.position)
    setDuration(local.duration || current.duration_ms)
    setCountdown(current.pending?.countdown && current.pending.status === "playing" && current.effective_at_ms > serverNow ? Math.ceil((current.effective_at_ms - serverNow) / 1000) : 0)
  }
  tickRef.current = tick
  useEffect(() => {
    const follow = window.setInterval(() => tickRef.current(), 250)
    const heartbeat = window.setInterval(() => {
      const local = localState()
      const current = stateRef.current
      if (!local || !current || clockRef.current === null) return
      channelRef.current?.push("playback.heartbeat", { position_ms: Math.round(local.position), duration_ms: Math.round(local.duration), paused: local.paused, buffering: local.buffering, drift_ms: local.position - targetPosition(current, performance.now() + clockRef.current) })
    }, 1500)
    return () => { window.clearInterval(follow); window.clearInterval(heartbeat); window.clearTimeout(stallTimerRef.current) }
  }, [])
  useEffect(() => {
    const video = videoRef.current
    if (!video) return
    for (const track of Array.from(video.textTracks)) track.mode = track.language === subtitle ? "showing" : "disabled"
  }, [subtitle, playback?.subtitles])
  useEffect(() => {
    chatEndRef.current?.scrollIntoView({ block: "nearest", behavior: "smooth" })
  }, [chat.length])
  useEffect(() => {
    if (!reactions.length) return
    const wait = Math.max(0, reactions[0].at + 2200 - Date.now())
    const timer = window.setTimeout(() => {
      const cutoff = Date.now() - 2100
      setReactions((items) => items.filter((item) => item.at > cutoff))
    }, wait)
    return () => window.clearTimeout(timer)
  }, [reactions])

  async function togglePlay(countdownStart = false) {
    const local = localState()
    const current = stateRef.current
    if (playRequestRef.current || (current?.pending?.countdown && clockRef.current !== null && current.effective_at_ms > performance.now() + clockRef.current)) return
    if (!canControl || !local?.ready || !connected) { setStatus("Tunggu player siap sebelum memulai"); return }
    if (playing && !countdownStart) { command("playback.pause", { position_ms: Math.round(local.position) }); return }
    playRequestRef.current = true
    setStartPending(true)
    if (!isYoutube && !await activatePlayer()) { playRequestRef.current = false; setStartPending(false); return }
    const reset = () => { playRequestRef.current = false; setStartPending(false) }
    const push = command(countdownStart ? "playback.countdown" : "playback.play", { position_ms: Math.round(localState()?.position || local.position) })
    if (!push) { reset(); return }
    push.receive("ok", (data) => { applyRef.current(data as unknown as Snapshot); setStatus("Pemutaran dijadwalkan bersama"); reset() }).receive("error", reset).receive("timeout", reset)
  }
  function applyFilmOutput() {
    const silent = filmMutedRef.current || duckedRef.current
    const level = silent ? 0 : volumeRef.current
    const video = videoRef.current
    if (video) { video.volume = level; video.muted = silent }
    const yt = ytRef.current
    if (!yt) return
    try {
      yt.setVolume(Math.round(level * 100))
      if (silent) yt.mute(); else yt.unMute()
    } catch { /* The official player rejects calls before its ready event. */ }
  }
  applyFilmRef.current = applyFilmOutput
  function onSpeechDuck(active: boolean) {
    duckedRef.current = active
    applyFilmOutput()
  }
  function changeVolume(value: number, mute = value === 0) {
    volumeRef.current = value
    filmMutedRef.current = mute
    setVolume(value); setMuted(mute)
    applyFilmOutput()
  }
  async function resync() {
    try {
      const data = await api<{ snapshot: Snapshot }>(`/api/v1/rooms/${code}/playback`)
      applyRef.current(data.snapshot)
      if (clockRef.current !== null) seekLocal(targetPosition(data.snapshot, performance.now() + clockRef.current))
      setStatus("Posisi disamakan dengan ruang")
    } catch (error) { setStatus(error instanceof Error ? error.message : "Gagal sinkronisasi") }
  }
  async function loadPlaylist() {
    try { const data = await api<{ items: Playlist[] }>(`/api/v1/rooms/${code}/playlist`); setPlaylist(data.items) } catch { /* Guests can continue watching if playlist is unavailable. */ }
  }
  async function action(path: string, body: object) {
    try { await api(`/api/v1/rooms/${code}/${path}`, { method: "POST", body: JSON.stringify(body) }); return true }
    catch (error) { setStatus(error instanceof Error ? error.message : "Gagal menyimpan"); return false }
  }
  function activeFullscreen() {
    const doc = document as Document & { webkitFullscreenElement?: Element | null }
    return document.fullscreenElement || doc.webkitFullscreenElement || null
  }
  function toggleFullscreen() {
    const frame = frameRef.current
    if (!frame) return
    const active = activeFullscreen() === frame
    const vendorFrame = frame as HTMLDivElement & { webkitRequestFullscreen?: () => void }
    const vendorDoc = document as Document & { webkitExitFullscreen?: () => void }
    try {
      const pending = active
        ? (document.exitFullscreen?.() ?? vendorDoc.webkitExitFullscreen?.())
        : (frame.requestFullscreen?.() ?? vendorFrame.webkitRequestFullscreen?.())
      if (pending && typeof (pending as Promise<void>).then === "function") {
        void (pending as Promise<void>).catch(() => setStatus(active ? "Tidak bisa mengecilkan layar" : "Layar penuh ditolak browser"))
      } else if (pending == null && !active) setStatus("Layar penuh tidak tersedia di browser ini")
    } catch { setStatus(active ? "Tidak bisa mengecilkan layar" : "Layar penuh ditolak browser") }
  }
  useEffect(() => {
    const frame = playerNode
    if (!fullscreen || chatOpen || !frame) { setControlsIdle(false); return }
    let timer = 0
    const wake = () => {
      setControlsIdle(false)
      window.clearTimeout(timer)
      timer = window.setTimeout(() => {
        // Keep controls up while the pointer or keyboard focus is on them.
        if (frame.querySelector(".player-controls:hover, .player-controls :focus-visible")) return
        setControlsIdle(true)
      }, 2500)
    }
    wake()
    frame.addEventListener("pointermove", wake)
    frame.addEventListener("pointerdown", wake)
    frame.addEventListener("keydown", wake)
    return () => {
      window.clearTimeout(timer)
      frame.removeEventListener("pointermove", wake)
      frame.removeEventListener("pointerdown", wake)
      frame.removeEventListener("keydown", wake)
    }
  }, [fullscreen, chatOpen, playerNode])
  useEffect(() => {
    const sync = () => setFullscreen(activeFullscreen() === frameRef.current)
    document.addEventListener("fullscreenchange", sync)
    document.addEventListener("webkitfullscreenchange", sync)
    return () => {
      document.removeEventListener("fullscreenchange", sync)
      document.removeEventListener("webkitfullscreenchange", sync)
    }
  }, [])
  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      const element = event.target as HTMLElement
      if (element.closest("input,textarea,select,button,[contenteditable=true]") || event.ctrlKey || event.metaKey || event.altKey) return
      if (event.key.toLowerCase() === "f") toggleFullscreen()
      if (event.key.toLowerCase() === "m") changeVolume(volume, !muted)
      if (canControl && event.code === "Space") { event.preventDefault(); togglePlay() }
      if (canControl && ["ArrowRight", "ArrowLeft"].includes(event.key)) { event.preventDefault(); command("playback.seek", { position_ms: Math.max(0, Math.min(duration, position + (event.key === "ArrowRight" ? 5000 : -5000))) }) }
    }
    window.addEventListener("keydown", onKey)
    return () => window.removeEventListener("keydown", onKey)
  })
  useEffect(() => {
    const dialog = queueDialogRef.current
    if (queueOpen && dialog && !dialog.open) dialog.showModal()
    else if (!queueOpen && dialog?.open) dialog.close()
  }, [queueOpen])
  useEffect(() => {
    if (!queueOpen) return
    const abort = new AbortController()
    const timer = window.setTimeout(() => {
      setQueueLoading(true); setQueueError("")
      void api<{ items: Media[]; total: number }>(`/api/v1/media?status=ready&per_page=20&page=${queuePage}&q=${encodeURIComponent(queueSearch)}`, { signal: abort.signal })
        .then((data) => { if (!abort.signal.aborted) { setQueueFilms(data.items); setQueueTotal(data.total) } })
        .catch((error: Error) => { if (!abort.signal.aborted) setQueueError(error.message) })
        .finally(() => { if (!abort.signal.aborted) setQueueLoading(false) })
    }, 250)
    return () => { window.clearTimeout(timer); abort.abort() }
  }, [queueOpen, queueSearch, queuePage])
  async function addToQueue(id: string) {
    setAddingFilm(id)
    setQueueError("")
    try {
      await api(`/api/v1/rooms/${code}/playlist`, { method: "POST", body: JSON.stringify({ media_id: id }) })
      await loadPlaylist()
      setStatus("Film ditambahkan. Film aktif tetap berjalan.")
    } catch (error) { setQueueError(error instanceof Error ? error.message : "Gagal menambahkan film") }
    finally { setAddingFilm(null) }
  }
  async function selectQueuedFilm(id: string) {
    if (queueBusy) return
    setQueueBusy(true)
    try {
      const data = await api<{ snapshot: Snapshot }>(`/api/v1/rooms/${code}/media`, { method: "POST", body: JSON.stringify({ media_id: id }) })
      applyRef.current(data.snapshot)
      await loadPlaylist()
      setStatus("Film dipilih. Tekan Mulai bareng setelah player siap; antrean lainnya tetap tersimpan.")
    } catch (error) { setStatus(error instanceof Error ? error.message : "Gagal memilih film") }
    finally { setQueueBusy(false) }
  }
  async function removeQueuedFilm(id: string) {
    if (queueBusy) return
    setQueueBusy(true)
    try {
      await api(`/api/v1/rooms/${code}/playlist/${id}`, { method: "DELETE" })
      await loadPlaylist()
      setStatus("Film dihapus dari antrean. Film aktif tetap berjalan.")
    } catch (error) { setStatus(error instanceof Error ? error.message : "Gagal menghapus antrean") }
    finally { setQueueBusy(false) }
  }
  const canChat = chatPermission === "everyone" || (chatPermission === "host_mod" && canControl)
  const chatAside = <aside className={fullscreen ? "chat-panel chat-dock" : "chat-panel"}><div className="chat-heading"><div><span className="eyebrow">LIVE CONVERSATION</span><h2>Obrolan ruang</h2></div><span className="live-dot" /></div><div className="chat-messages" role="log" aria-label="Pesan ruang" aria-live="polite">{!chat.length ? <div className="chat-empty"><span>✦</span><h3>Film lebih seru bersama.</h3><p>Sapa temanmu, bahas adegan favorit, dan nikmati malamnya.</p></div> : chat.map((item) => { const mine = item.member_id ? item.member_id === memberRef.current : people.find((person) => person.id === memberRef.current)?.display_name === item.display_name; const sent = item.inserted_at ? new Date(item.inserted_at).toLocaleTimeString("id-ID", { hour: "2-digit", minute: "2-digit" }) : ""; return <div className={mine ? "chat-row mine" : "chat-row"} key={item.id}><div className="chat-bubble">{mine ? null : <strong>{item.display_name}</strong>}<p>{item.body}</p>{sent ? <time>{sent}</time> : null}</div></div> })}<div ref={chatEndRef} /></div><div className="emoji-row">{["❤️", "😂", "🔥", "😮", "👏"].map((emoji) => <button key={emoji} aria-label={`Reaksi ${emoji}`} onClick={() => command("reaction.send", { emoji })}>{emoji}</button>)}</div><form className="chat-form" onSubmit={(event) => { event.preventDefault(); if (!draft.trim() || sending || !canChat) return; setSending(true); command("chat.send", { body: draft.trim() })?.receive("ok", () => { setDraft(""); setSending(false) }).receive("error", () => setSending(false)).receive("timeout", () => setSending(false)) }}><input aria-label="Pesan chat" maxLength={500} disabled={!connected || !canChat} placeholder={canChat ? "Tulis pesan…" : "Chat dibatasi host"} value={draft} onChange={(event) => setDraft(event.target.value)} /><button disabled={!connected || !canChat || !draft.trim() || sending} aria-label="Kirim pesan">↑</button></form><p className="chat-footnote">Satu film. Satu momen. Bersama.</p></aside>
  const chatSlot = chatOpen ? (fullscreen && playerNode ? createPortal(chatAside, playerNode) : chatAside) : null
  return (
    <main className={`watch-page ${theater ? "theater-mode" : ""}`}>
      <header className="watch-header"><Brand /><div><Badge tone={connected ? "green" : "amber"}>{connected ? "Terhubung" : "Menghubungkan"}</Badge><ThemeToggle /><Link to={`/rooms/${code}`} className="secondary-button">Kelola ruang</Link></div></header>
      <div className={`watch-grid ${!chatOpen ? "chat-collapsed" : ""}`}>
        <section className="min-w-0">
          <div ref={(node) => { frameRef.current = node; setPlayerNode((current) => current === node ? current : node) }} className={`cinema-player${fullscreen && chatOpen ? " with-chat" : ""}${controlsIdle ? " controls-idle" : ""}`}>
            <video ref={videoRef} className={isYoutube ? "hidden" : "aspect-video w-full"} playsInline crossOrigin="use-credentials" preload="auto" poster={playback?.poster_key ? `/media/t/${playback.token}/${playback.poster_key}` : undefined}
              onWaiting={reportWaiting} onSeeking={() => setLoading(true)} onCanPlay={() => { setLoading(false); signal(false); tickRef.current() }} onPlaying={() => { setLoading(false); setBlocked(false); signal(false) }} onEnded={() => { if (canControl) command("playback.pause", { position_ms: Math.round(duration) }) }}>
              {playback?.subtitles?.map((sub) => <track key={sub.language} kind="subtitles" srcLang={sub.language} label={sub.label} src={`/media/t/${playback.token}/${sub.vtt_key}`} />)}
            </video>
            <div ref={ytNodeRef} className={`youtube-frame ${isYoutube ? "" : "hidden"}`} />
            {isYoutube ? <div className="absolute inset-0 bottom-24" aria-hidden="true" /> : null}
            <div className="player-topline"><span>◉ {code}</span><span>{canControl ? "KONTROL HOST" : "MENGIKUTI HOST"}</span></div>
            {processing ? <div className="player-message"><div><h2>{processing.status === "failed" ? "Pengolahan gagal" : "Menyiapkan film"}</h2><p>{processing.error || "Film muncul otomatis setelah pengolahan selesai."}</p><progress max={100} value={processing.progress} /><p>{Math.round(processing.progress)}% · {processing.status}</p></div></div> : null}
            {countdown > 0 ? <div className="countdown-overlay" aria-live="polite"><span>{countdown}</span><p>Bersiap, mulai bersama</p></div> : null}
            {!playback && !processing ? <div className="player-message"><div><h2>{!snapshot ? "Menghubungkan ke ruang…" : snapshot.media_id ? "Menyiapkan pemutar…" : "Host belum memilih film"}</h2><p>{!snapshot || snapshot.media_id ? status : "Pilih film dari pengaturan ruang untuk mulai menonton."}</p></div></div> : null}
            {loading && playback && !countdown ? <span className="player-loading"><i /> Memuat buffer</span> : null}
            {blocked ? <button className="activate-player" onClick={() => { changeVolume(volume, false); void activatePlayer().then((ok) => { if (ok) tickRef.current() }) }}>Siap Nonton — Aktifkan Player</button> : null}
            <div className="reaction-overlay" aria-hidden="true">{reactions.map((item) => <span key={item.id} className={item.burst ? "reaction-pop burst" : "reaction-pop"} style={{ "--dx": `${item.dx}px`, "--dy": `${item.dy}px` } as CSSProperties}>{item.emoji}{item.burst || !item.display_name ? null : <small>{item.display_name}</small>}</span>)}</div>
            <div className="player-controls">
              <input aria-label={canControl ? "Posisi pemutaran bersama" : "Posisi film, dikendalikan host"} className="timeline" type="range" min={0} max={duration || 1} step={1000} value={Math.min(position, duration || 1)} disabled={!canControl || !connected} onChange={(event) => command("playback.seek", { position_ms: Number(event.target.value) })} />
              <div className="control-row">
                {canControl ? <button className="control-icon" disabled={!connected || !playback || loading} aria-label={playing ? "Jeda" : "Putar"} onClick={() => togglePlay()}>{playing ? "❚❚" : "▶"}</button> : null}
                <button className="control-icon" aria-label={muted ? "Aktifkan suara" : "Senyapkan"} onClick={() => changeVolume(volume, !muted)}>{muted ? "♪̸" : "♪"}</button>
                <input aria-label="Volume" className="volume-slider" type="range" min={0} max={1} step={0.05} value={muted ? 0 : volume} onChange={(event) => changeVolume(Number(event.target.value))} />
                <span className="player-time">{clock(position)} <span>/ {clock(duration)}</span></span>
                <div className="control-spacer" />
                {levels.length ? <select aria-label="Kualitas video" value={quality} onChange={(event) => { const next = Number(event.target.value); setQuality(next); if (hlsRef.current) hlsRef.current.nextLevel = next }}><option value={-1}>Auto</option>{levels.map((item) => <option key={item.index} value={item.index}>{item.label}</option>)}</select> : null}
                {playback?.subtitles?.length ? <select aria-label="Subtitle" value={subtitle} onChange={(event) => setSubtitle(event.target.value)}><option value="">CC · Mati</option>{playback.subtitles.map((item) => <option key={item.language} value={item.language}>{item.label}</option>)}</select> : null}
                <button type="button" className="control-icon control-text" aria-pressed={chatOpen} aria-label={chatOpen ? "Sembunyikan chat" : "Tampilkan chat"} onClick={() => setChatOpen((open) => !open)}>Chat</button>
                {fullscreen || !micOpen ? <button type="button" className="control-icon control-text" aria-pressed={micOpen} aria-label={micOpen ? "Sembunyikan mic" : "Tampilkan mic"} onClick={() => setMicOpen((open) => !open)}>Mic</button> : null}
                <span ref={setMicSlot} className="mic-slot" />
                {fullscreen ? null : <button type="button" className="control-icon" aria-label="Mode teater" onClick={() => setTheater(!theater)}>▭</button>}
                <button type="button" className="control-icon" aria-pressed={fullscreen} aria-label={fullscreen ? "Keluar layar penuh" : "Layar penuh"} onClick={() => toggleFullscreen()}>⛶</button>
              </div>
            </div>
          </div>
          <div className="watch-title"><div><p className="eyebrow">Ruang {code}</p><h1>{playback?.title || roomTitle}</h1><p role="status">{status}</p></div><button className="secondary-button" onClick={() => setChatOpen(!chatOpen)}>{chatOpen ? "Sembunyikan chat" : "Tampilkan chat"}</button></div>
          <div className="room-toolbar">
            <Badge tone={metrics?.host_buffering ? "amber" : "green"}>{metrics?.host_buffering ? "Host buffering · ruang dijeda" : playing ? "Sedang diputar" : "Dijeda"}</Badge>
            <button className="secondary-button" onClick={() => void resync()}>↻ Sinkronkan saya</button>
            {canControl ? <><Button disabled={loading || !connected || startPending || countdown > 0} onClick={() => void togglePlay(true)}>{startPending ? "Menyiapkan player…" : countdown > 0 ? `Mulai dalam ${countdown}…` : "▶ Mulai bareng · 3 detik"}</Button><button className="secondary-button" onClick={() => command("playback.sync", { status: "paused", position_ms: Math.round(position) })}>Jeda & samakan semua</button></> : null}
            {canControl && playback ? <label className="secondary-button cursor-pointer">＋ Subtitle .vtt<input className="sr-only" type="file" accept=".vtt,text/vtt" onChange={(event) => { const file = event.target.files?.[0]; event.currentTarget.value = ""; if (!file) return; if (file.size > 2_000_000) { setStatus("Subtitle maksimal 2 MB"); return }; void file.text().then((content) => api<{ subtitle: Playback["subtitles"][number] }>(`/api/v1/media/${playback.media_id}/subtitles`, { method: "POST", body: JSON.stringify({ language: (file.name.match(/^[a-z]{2,3}/i)?.[0] || "id").toLowerCase(), label: file.name.replace(/\.vtt$/i, ""), content }) })).then((data) => { setPlayback((previous) => previous ? { ...previous, subtitles: [...previous.subtitles.filter((sub) => sub.language !== data.subtitle.language), data.subtitle] } : previous); setSubtitle(data.subtitle.language); setStatus("Subtitle ditambahkan") }).catch((error: Error) => setStatus(error.message)) }} /></label> : null}
            <button className="secondary-button" onClick={async () => { const next = !ready; if (await action("ready", { ready: next })) setReady(next) }}>{ready ? "✓ Saya siap" : "Saya siap nonton"}</button>
            <button className="secondary-button" onClick={() => void navigator.clipboard.writeText(`${window.location.origin}/j/${code}`).then(() => setStatus("Tautan undangan disalin")).catch(() => setStatus(`Tautan: ${window.location.origin}/j/${code}`))}>Undang teman ↗</button>
          </div>
          <section className="audience-panel"><div className="section-title"><div><h2>Menonton bersama <span>{people.length}</span></h2></div><small>Selisih pemutaran terhadap host</small></div><div className="audience-grid">
            {people.map((person) => { const metric = metrics?.members.find((item) => item.member_id === person.id); const stale = !metric || Date.now() - metric.updated_at_ms > 8000; const lag = metric?.lag_ms || 0; return <article key={person.id} className="audience-card"><div className={`avatar ${person.role === "host" ? "host-avatar" : ""}`}>{person.display_name.charAt(0).toUpperCase()}</div><div className="min-w-0 flex-1"><strong className="block truncate">{person.display_name}{person.id === memberRef.current ? " (kamu)" : ""}</strong><small>{person.role === "host" ? "♛ Host" : person.role === "moderator" ? "Moderator" : "Penonton"}{readiness[person.id] ? " · ✓ Siap" : ""}</small><div className="mt-2"><Badge tone={stale || metric?.buffering ? "amber" : Math.abs(lag) > 1500 ? "red" : "green"}>{stale ? "Menunggu status" : metric?.buffering ? "Buffering" : Math.abs(lag) <= 500 ? "Tersinkron" : `${lag > 0 ? "Lebih cepat" : "Tertinggal"} ${lagLabel(lag)}`}</Badge></div></div>{role === "host" && person.role !== "host" ? <details className="member-menu"><summary aria-label={`Kelola ${person.display_name}`}>•••</summary><button onClick={() => void action("transfer-host", { member_id: person.id })}>Jadikan host</button><button onClick={() => void action("kick", { member_id: person.id })}>Keluarkan</button></details> : null}</article> })}
            {!people.length ? <p className="text-sm text-mist">Menghubungkan peserta…</p> : null}
          </div></section>
          <VoiceCall code={code} roomConnected={connected} dock={playerNode} joinDock={micSlot} fullscreen={fullscreen} showMic={micOpen} onSpeechDuck={onSpeechDuck} />
          <section className="audience-panel"><div className="section-title"><div><p className="eyebrow">UP NEXT</p><h2>Antrean malam ini <span>{playlist.length} film</span></h2><p className="mt-2 text-xs text-mist">Satu film aktif, banyak film dalam antrean. Menambah antrean tidak mengganti film yang sedang ditonton.</p></div>{canControl ? <Button onClick={() => setQueueOpen(true)}>＋ Tambah film</Button> : null}</div>{playlist.length ? playlist.map((item, index) => <div className="queue-row" key={item.id}><span className="queue-number">{String(index + 1).padStart(2, "0")}</span><strong>{item.media?.title || "Film dihapus"}</strong><button className="secondary-button" onClick={() => void action(`playlist/${item.id}/vote`, {}).then(() => loadPlaylist())}>♡ {item.votes}</button>{canControl && item.media?.status === "ready" ? <button className="secondary-button" disabled={queueBusy || !connected} onClick={() => void selectQueuedFilm(item.media!.id)}>Pilih film ini</button> : null}{canControl ? <button className="secondary-button" disabled={queueBusy} onClick={() => void removeQueuedFilm(item.id)}>Hapus antrean</button> : null}</div>) : <p className="text-sm text-mist">Belum ada antrean. Host dapat menambahkan film melalui tombol Tambah film.</p>}</section>
        </section>
        {chatSlot}

      </div>
      {canControl ? <dialog ref={queueDialogRef} onClose={() => setQueueOpen(false)} className="m-auto w-[min(640px,calc(100vw-2rem))] max-h-[85vh] overflow-auto rounded-2xl border border-line bg-panel p-6 text-ink shadow-2xl backdrop:bg-black/75"><div className="mb-5 flex items-center justify-between gap-3"><div><p className="eyebrow">PROGRAM MALAM INI</p><h2 className="mt-2 text-2xl font-semibold">Tambah film ke antrean</h2></div><button className="secondary-button" aria-label="Tutup pemilih film" onClick={() => setQueueOpen(false)}>✕</button></div><input autoFocus aria-label="Cari film untuk antrean" placeholder="Cari judul film…" className="mb-4 w-full rounded-xl border border-line p-3" value={queueSearch} onChange={(event) => { setQueueSearch(event.target.value); setQueuePage(1) }} /><p className="mb-4 text-xs text-mist">Film yang sudah selesai diolah muncul di sini. <Link to="/upload" className="text-amber underline">Unggah film baru ↗</Link></p>{queueError ? <p role="alert" className="mb-3 text-sm text-red-300">{queueError}</p> : null}{queueLoading ? <p role="status" className="py-5 text-mist">Memuat pustaka…</p> : queueFilms.length ? <div className="space-y-2">{queueFilms.map((film) => { const queued = playlist.some((item) => item.media?.id === film.id); const currentFilm = snapshot?.media_id === film.id; return <div key={film.id} className="flex items-center gap-3 rounded-xl border border-line p-3"><div className="min-w-0 flex-1"><strong className="block truncate text-sm">{film.title}</strong><small className="text-mist">{film.provider === "youtube" ? "YouTube" : "HLS"} · {clock(film.duration_ms || 0)}</small></div><Button tone={queued ? "ghost" : "amber"} disabled={queued || currentFilm || addingFilm !== null} onClick={() => void addToQueue(film.id)}>{currentFilm ? "Sedang aktif" : queued ? "✓ Dalam antrean" : addingFilm === film.id ? "Menambahkan…" : "＋ Tambahkan"}</Button></div> })}</div> : <p className="py-6 text-sm text-mist">Belum ada film siap yang sesuai. Unggah film lalu tunggu pengolahannya selesai.</p>}{queueTotal > 20 ? <div className="mt-5 flex items-center justify-between"><Button tone="ghost" disabled={queuePage <= 1 || queueLoading} onClick={() => setQueuePage(queuePage - 1)}>← Sebelumnya</Button><span className="text-xs text-mist">{queuePage} / {Math.ceil(queueTotal / 20)}</span><Button tone="ghost" disabled={queuePage * 20 >= queueTotal || queueLoading} onClick={() => setQueuePage(queuePage + 1)}>Berikutnya →</Button></div> : null}</dialog> : null}
    </main>
  )
}

function clock(ms: number) { const seconds = Math.max(0, Math.floor(ms / 1000)); const h = Math.floor(seconds / 3600); return `${h ? `${h}:` : ""}${String(Math.floor(seconds / 60) % 60).padStart(h ? 2 : 1, "0")}:${String(seconds % 60).padStart(2, "0")}` }
function lagLabel(ms: number) { const seconds = Math.abs(ms) / 1000; return seconds >= 60 ? `${Math.floor(seconds / 60)} menit ${Math.round(seconds % 60)} detik` : `${seconds.toFixed(1)} detik` }
async function sampleClock(channel: Channel) {
  const samples: ClockSample[] = []
  for (let i = 0; i < 4; i++) {
    const t0 = performance.now()
    const sample = await new Promise<ClockSample>((resolve, reject) => {
      channel.push("clock.ping", { t0 }).receive("ok", (data) => resolve({ t0, server: Number(data.server_wall_ms), t1: performance.now() })).receive("timeout", () => reject(new Error("Clock timeout"))).receive("error", () => reject(new Error("Clock unavailable")))
    })
    if (Number.isFinite(sample.server)) samples.push(sample)
  }
  if (!samples.length) throw new Error("Clock unavailable")
  return estimateOffset(samples).offset
}
