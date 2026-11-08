import { useEffect, useRef, useState } from "react"
import { VoiceSession, type VoicePeer } from "./voice"

export function VoiceCall({ code, roomConnected }: { code: string; roomConnected: boolean }) {
  const session = useRef<VoiceSession | null>(null)
  const [state, setState] = useState("idle")
  const [peers, setPeers] = useState<VoicePeer[]>([])
  const [message, setMessage] = useState("")
  const [muted, setMuted] = useState(false)
  const [volume, setVolume] = useState(80)
  const [devices, setDevices] = useState<MediaDeviceInfo[]>([])
  const [device, setDevice] = useState("")
  useEffect(() => {
    const refresh = () => { void navigator.mediaDevices?.enumerateDevices().then(items => setDevices(items.filter(d => d.kind === "audioinput"))).catch(() => {}) }
    refresh()
    navigator.mediaDevices?.addEventListener("devicechange", refresh)
    return () => { session.current?.close(); navigator.mediaDevices?.removeEventListener("devicechange", refresh) }
  }, [])
  async function join() {
    if (session.current || !roomConnected) return
    setState("joining"); setMessage(""); setMuted(false)
    const current = new VoiceSession(setPeers, setMessage, () => { session.current = null; setState("idle"); setPeers([]) })
    session.current = current
    current.setVolume(volume / 100)
    try {
      await current.join(code, device)
      if (session.current !== current) return
      setState("active")
      const items = await navigator.mediaDevices.enumerateDevices()
      setDevices(items.filter(d => d.kind === "audioinput"))
    } catch (error) {
      current.close()
      if (session.current !== current) return
      session.current = null; setState("idle")
      const name = error instanceof Error ? error.name : ""
      setMessage(name === "NotAllowedError" ? "Izin mikrofon ditolak. Izinkan mikrofon lewat pengaturan situs, lalu coba lagi." : name === "NotFoundError" ? "Mikrofon tidak ditemukan. Sambungkan mikrofon terlebih dahulu." : error instanceof Error ? error.message : "Gagal membuka call.")
    }
  }
  function leave() { session.current?.close(); session.current = null; setState("idle"); setPeers([]); setMessage("") }
  return <section className="audience-panel voice-panel" aria-label="Voice call">
    <div className="section-title"><div><p className="eyebrow">VOICE LOUNGE</p><h2>Ngobrol sambil nonton <span>{peers.length}/8</span></h2><p className="mt-2 text-xs text-mist">Audio film dan call punya volume terpisah. Mikrofon hanya aktif setelah Anda bergabung.</p></div>
      {state === "idle" ? <button className="primary-button" disabled={!roomConnected} onClick={() => void join()}>Gabung call</button> : <button className="secondary-button" onClick={leave}>{state === "joining" ? "Batalkan call" : "Keluar call"}</button>}</div>
    <div className="flex flex-wrap items-center gap-3 mt-4">
      <label className="text-sm">Mikrofon <select aria-label="Mikrofon call" disabled={state !== "idle"} value={device} onChange={e => setDevice(e.target.value)}><option value="">Perangkat default</option>{devices.filter(d => d.deviceId).map((d, i) => <option value={d.deviceId} key={d.deviceId}>{d.label || `Mikrofon ${i + 1}`}</option>)}</select></label>
      {state === "active" ? <><button className="secondary-button" aria-pressed={muted} onClick={() => { session.current?.mute(!muted); setMuted(!muted) }}>{muted ? "Nyalakan mikrofon" : "Bisukan mikrofon"}</button><button className="secondary-button" onClick={() => { setMessage(""); session.current?.resumeAudio() }}>Aktifkan suara call</button></> : null}
      <label className="flex items-center gap-2 text-sm">Volume call <input aria-label="Volume call" type="range" min="0" max="100" value={volume} onChange={e => { const next = Number(e.target.value); setVolume(next); session.current?.setVolume(next / 100) }} /><span>{volume}%</span></label>
    </div>
    <p role="status" className="text-sm text-mist mt-3">{message || (state === "joining" ? "Meminta izin mikrofon dan menghubungkan…" : state === "active" ? "Call aktif · melalui koneksi ruang · volume film terpisah." : !roomConnected ? "Menunggu koneksi ruang sebelum bergabung call." : "Call opsional · maksimal 8 peserta agar ringan.")}</p>
    <div className="flex flex-wrap gap-2 mt-3">{peers.map(peer => <span className="voice-person" data-state={peer.state} data-received-frames={peer.receivedFrames} key={peer.id}>{peer.muted ? "🔇" : "🎙"} {peer.name} · {peer.state === "connected" ? "Terhubung" : peer.state === "failed" ? "Gagal" : peer.state === "disconnected" ? "Terputus" : "Menghubungkan"}</span>)}</div>
    <details className="mt-3 text-xs text-mist"><summary>Suara film mengecil saat call?</summary><p className="mt-2">Aplikasi tidak menurunkan volume film. Di Windows, pilih Sound → Communications → Do nothing. Jika memakai headset Bluetooth, coba mikrofon laptop/USB agar headset tidak beralih ke mode telepon. Headphone membantu mencegah gema.</p></details>
  </section>
}
