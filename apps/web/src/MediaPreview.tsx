import Hls from "hls.js"
import { useEffect, useRef, useState } from "react"
import { api, type Media } from "./api"
import { Button } from "./ui"

type Playback = { media_id: string; token: string; expires_at: number; playback: { kind: string; manifest_key?: string; youtube_id?: string } }

export default function MediaPreview({ media, onClose }: { media: Media; onClose: () => void }) {
  const dialog = useRef<HTMLDialogElement>(null)
  const video = useRef<HTMLVideoElement>(null)
  const token = useRef("")
  const [playback, setPlayback] = useState<Playback | null>(null)
  const [error, setError] = useState("")
  const [loading, setLoading] = useState(true)
  const [retry, setRetry] = useState(0)
  useEffect(() => { if (!dialog.current?.open) dialog.current?.showModal() }, [])
  useEffect(() => {
    const abort = new AbortController()
    let timer = 0
    async function load() {
      try {
        const next = await api<Playback>("/api/v1/playback/token", { method: "POST", body: JSON.stringify({ media_id: media.id }), signal: abort.signal })
        if (abort.signal.aborted) return
        if (!["hls", "youtube"].includes(next.playback.kind)) throw new Error("Jenis media ini belum mendukung pratinjau.")
        token.current = next.token
        setPlayback(next)
        timer = window.setTimeout(() => void load(), Math.max(10000, next.expires_at * 1000 - Date.now() - 120000))
      } catch (failure) { if (!abort.signal.aborted) { setError(failure instanceof Error ? failure.message : "Pratinjau gagal dimuat."); setLoading(false) } }
    }
    void load()
    return () => { abort.abort(); window.clearTimeout(timer) }
  }, [media.id, retry])
  const kind = playback?.playback.kind
  const manifest = playback?.playback.manifest_key
  useEffect(() => {
    const node = video.current
    if (!node || kind !== "hls" || !manifest) return
    const url = `/media/t/${token.current}/${manifest}`
    let hls: Hls | undefined
    if (Hls.isSupported()) {
      hls = new Hls({ maxBufferLength: 15, backBufferLength: 10, xhrSetup: (xhr, requestUrl) => {
        if (requestUrl.includes("/media/t/")) xhr.open("GET", requestUrl.replace(/\/media\/t\/[^/]+\//, `/media/t/${token.current}/`), true)
      } })
      hls.loadSource(url)
      hls.attachMedia(node)
      hls.on(Hls.Events.MANIFEST_PARSED, () => setLoading(false))
      hls.on(Hls.Events.ERROR, (_, data) => { if (data.fatal) { setError("Video gagal dimuat. Coba ulang atau periksa hasil pengolahan film."); setLoading(false) } })
    } else if (node.canPlayType("application/vnd.apple.mpegurl")) { /* Native HLS credentials are applied in the effect below. */ }
    else { setError("Browser ini belum mendukung pemutaran HLS."); setLoading(false) }
    return () => { hls?.destroy(); node.pause(); node.removeAttribute("src"); node.load() }
  }, [kind, manifest, retry])
  useEffect(() => {
    const node = video.current
    if (!node || kind !== "hls" || !manifest || !playback?.token || Hls.isSupported() || !node.canPlayType("application/vnd.apple.mpegurl")) return
    const position = node.currentTime
    const paused = node.paused
    const restore = () => { if (position > 0) node.currentTime = position; if (!paused) void node.play().catch(() => setError("Tekan Play untuk melanjutkan pratinjau.")) }
    node.addEventListener("loadedmetadata", restore, { once: true })
    node.src = `/media/t/${playback.token}/${manifest}`
    return () => node.removeEventListener("loadedmetadata", restore)
  }, [playback?.token, kind, manifest, retry])
  return <dialog ref={dialog} className="media-dialog preview-dialog" aria-labelledby="preview-title" onClose={onClose}>
    <header className="modal-heading"><div><h2 id="preview-title">{media.title}</h2><p>Pratinjau pribadi. Tidak mengubah pemutaran room.</p></div><button className="secondary-button" onClick={onClose}>Tutup</button></header>
    {kind === "youtube" && playback?.playback.youtube_id ? <iframe title={`Pratinjau ${media.title}`} src={`https://www.youtube-nocookie.com/embed/${encodeURIComponent(playback.playback.youtube_id)}`} className="preview-video" allow="autoplay; encrypted-media; picture-in-picture" allowFullScreen onLoad={() => setLoading(false)} /> : <video ref={video} className="preview-video" controls playsInline preload="metadata" onLoadedMetadata={() => setLoading(false)} onError={() => { setError("Browser tidak dapat membuka video ini."); setLoading(false) }} />}
    {loading ? <p role="status" className="form-note mt-4">Memuat pratinjau…</p> : null}
    {error ? <div className="mt-4"><p role="alert">{error}</p><Button tone="ghost" className="mt-3" onClick={() => { setError(""); setLoading(true); setRetry(retry + 1) }}>Coba ulang</Button></div> : null}
  </dialog>
}
