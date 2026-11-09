import { useEffect, useRef, useState, type KeyboardEvent, type PointerEvent } from "react"
import { createPortal } from "react-dom"
import { VoiceSession, type VoicePeer } from "./voice"

export function VoiceCall({ code, roomConnected, dock, onSpeechDuck }: {
  code: string
  roomConnected: boolean
  dock: HTMLElement | null
  onSpeechDuck: (active: boolean) => void
}) {
  const session = useRef<VoiceSession | null>(null)
  const alive = useRef(true)
  const holdingRef = useRef(false)
  const remoteRef = useRef(false)
  const holdTimer = useRef(0)
  const onSpeechDuckRef = useRef(onSpeechDuck)
  const endTalkRef = useRef<() => void>(() => {})
  const [state, setState] = useState("idle")
  const [peers, setPeers] = useState<VoicePeer[]>([])
  const [message, setMessage] = useState("")
  const [holding, setHolding] = useState(false)
  const [remoteSpeech, setRemoteSpeech] = useState(false)
  const [volume, setVolume] = useState(80)
  const [devices, setDevices] = useState<MediaDeviceInfo[]>([])
  const [device, setDevice] = useState("")
  onSpeechDuckRef.current = onSpeechDuck
  useEffect(() => {
    alive.current = true
    const refresh = () => { void navigator.mediaDevices?.enumerateDevices().then(items => setDevices(items.filter(d => d.kind === "audioinput"))).catch(() => {}) }
    refresh()
    navigator.mediaDevices?.addEventListener("devicechange", refresh)
    return () => {
      alive.current = false
      window.clearTimeout(holdTimer.current)
      holdingRef.current = false
      remoteRef.current = false
      session.current?.close()
      onSpeechDuckRef.current(false)
      navigator.mediaDevices?.removeEventListener("devicechange", refresh)
    }
  }, [])
  useEffect(() => {
    if (state !== "active") return
    const stop = () => { window.setTimeout(() => { if (!document.hasFocus() && document.activeElement?.tagName !== "IFRAME") endTalkRef.current() }, 0) }
    const onHide = () => { if (document.visibilityState !== "visible") stop() }
    window.addEventListener("blur", stop)
    document.addEventListener("visibilitychange", onHide)
    return () => {
      window.removeEventListener("blur", stop)
      document.removeEventListener("visibilitychange", onHide)
    }
  }, [state])
  function applyDuck() { onSpeechDuckRef.current(holdingRef.current || remoteRef.current) }
  function beginTalk(event: PointerEvent<HTMLButtonElement> | KeyboardEvent<HTMLButtonElement>) {
    event.preventDefault()
    if ("pointerId" in event) { try { event.currentTarget.setPointerCapture(event.pointerId) } catch { /* Synthetic presses have no active pointer. */ } }
    if (holdingRef.current) return
    holdingRef.current = true
    setHolding(true)
    applyDuck()
    session.current?.transmit(true)
    window.clearTimeout(holdTimer.current)
    holdTimer.current = window.setTimeout(() => {
      endTalkRef.current()
      setMessage("Mikrofon ditutup otomatis setelah 60 detik. Tahan lagi untuk melanjutkan.")
    }, 60000)
  }
  function endTalk() {
    window.clearTimeout(holdTimer.current)
    if (!holdingRef.current) return
    holdingRef.current = false
    setHolding(false)
    session.current?.transmit(false)
    applyDuck()
  }
  endTalkRef.current = endTalk
  function resetTalk() {
    window.clearTimeout(holdTimer.current)
    holdingRef.current = false
    remoteRef.current = false
    setHolding(false)
    setRemoteSpeech(false)
    if (alive.current) applyDuck()
    else onSpeechDuckRef.current(false)
  }
  async function join() {
    if (session.current || !roomConnected) return
    setState("joining"); setMessage(""); resetTalk()
    const current = new VoiceSession(setPeers, setMessage, () => {
      session.current = null
      setState("idle")
      setPeers([])
      resetTalk()
    }, (active) => {
      if (!alive.current) return
      remoteRef.current = active
      setRemoteSpeech(active)
      applyDuck()
    })
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
      session.current = null; setState("idle"); resetTalk()
      const name = error instanceof Error ? error.name : ""
      setMessage(name === "NotAllowedError" ? "Izin mikrofon ditolak. Izinkan mikrofon lewat pengaturan situs, lalu coba lagi." : name === "NotFoundError" ? "Mikrofon tidak ditemukan. Sambungkan mikrofon terlebih dahulu." : error instanceof Error ? error.message : "Gagal membuka call.")
    }
  }
  function leave() { session.current?.close(); session.current = null; setState("idle"); setPeers([]); setMessage(""); resetTalk() }
  const speaking = holding || remoteSpeech
  const talk = state === "active" && dock ? createPortal(
    <button type="button" className="talk-button" aria-pressed={holding} aria-label="Tahan untuk bicara" onContextMenu={(event) => event.preventDefault()} onPointerDown={beginTalk} onPointerUp={endTalk} onPointerCancel={endTalk} onLostPointerCapture={endTalk} onKeyDown={(event) => { if (event.repeat || (event.key !== " " && event.key !== "Enter")) return; beginTalk(event) }} onKeyUp={(event) => { if (event.key === " " || event.key === "Enter") { event.preventDefault(); endTalk() } }}>{holding ? "BICARA" : "MIC"}</button>,
    dock,
  ) : null
  return <>
    {talk}
    <section className="audience-panel voice-panel" aria-label="Voice call">
      <div className="section-title"><div><p className="eyebrow">VOICE LOUNGE</p><h2>Ngobrol sambil nonton <span>{peers.length}/8</span></h2><p className="mt-2 text-xs text-mist">Tahan tombol di film untuk bicara. Mikrofon tertutup sampai tombol ditekan, dan suara film senyap selama seseorang bicara.</p></div>
        {state === "idle" ? <button className="primary-button" disabled={!roomConnected} onClick={() => void join()}>Gabung call</button> : <button className="secondary-button" onClick={leave}>{state === "joining" ? "Batalkan call" : "Keluar call"}</button>}</div>
      <div className="flex flex-wrap items-center gap-3 mt-4">
        <label className="text-sm">Mikrofon <select aria-label="Mikrofon call" disabled={state !== "idle"} value={device} onChange={e => setDevice(e.target.value)}><option value="">Perangkat default</option>{devices.filter(d => d.deviceId).map((d, i) => <option value={d.deviceId} key={d.deviceId}>{d.label || `Mikrofon ${i + 1}`}</option>)}</select></label>
        {state === "active" ? <button className="secondary-button" onClick={() => { setMessage(""); session.current?.resumeAudio() }}>Aktifkan suara call</button> : null}
        <label className="flex items-center gap-2 text-sm">Volume call <input aria-label="Volume call" type="range" min="0" max="100" value={volume} onChange={e => { const next = Number(e.target.value); setVolume(next); session.current?.setVolume(next / 100) }} /><span>{volume}%</span></label>
      </div>
      <p role="status" className="text-sm text-mist mt-3">{message || (state === "joining" ? "Meminta izin mikrofon dan menghubungkan…" : state === "active" ? (speaking ? "Seseorang sedang bicara · suara film senyap." : "Call aktif · tahan tombol di film untuk bicara.") : !roomConnected ? "Menunggu koneksi ruang sebelum bergabung call." : "Call opsional · maksimal 8 peserta agar ringan.")}</p>
      <div className="flex flex-wrap gap-2 mt-3">{peers.map(peer => <span className="voice-person" data-state={peer.state} data-received-frames={peer.receivedFrames} key={peer.id}>{peer.muted ? "🔇" : "🎙"} {peer.name} · {peer.state === "connected" ? "Terhubung" : peer.state === "failed" ? "Gagal" : peer.state === "disconnected" ? "Terputus" : "Menghubungkan"}</span>)}</div>
      <details className="mt-3 text-xs text-mist"><summary>Suara film senyap saat bicara?</summary><p className="mt-2">Saat seseorang bicara, aplikasi mematikan suara film di perangkat ini supaya mikrofon tidak membawa soundtrack dan suara teman tetap terdengar. Slider film kembali setelah bicara selesai. Di Windows, pilih Sound → Communications → Do nothing agar sistem tidak mengubah volume di luar itu. Jika memakai headset Bluetooth, coba mikrofon laptop/USB agar headset tidak beralih ke mode telepon. Headphone membantu mencegah sisa gema suara orang.</p></details>
    </section>
  </>
}
