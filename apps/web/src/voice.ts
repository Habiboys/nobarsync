import captureSource from "./voice-capture.js?raw"
import { Socket, type Channel } from "phoenix"
import { api } from "./api"

export type VoicePeer = { id: string; name: string; muted: boolean; state: string; receivedFrames: number }
type Presence = Record<string, { metas: { display_name: string; muted: boolean }[] }>
type Playback = { next: number; frames: number; sequence: number; sources: Set<AudioBufferSourceNode> }

// Mean square of int16 samples. Quiet keepalive frames stay under the send gate.
const SILENCE_POWER = 2500
const SPEECH_HANGOVER_MS = 400

function micConstraints(deviceId: string): MediaStreamConstraints {
  return { video: false, audio: {
    deviceId: deviceId ? { exact: deviceId } : undefined,
    channelCount: 1, echoCancellation: true, noiseSuppression: true, autoGainControl: true,
  } }
}

// Voice travels through the authenticated same-origin WebSocket. No direct peer
// connection or external TURN endpoint is needed, including through HTTP ngrok.
export class VoiceSession {
  private socket?: Socket
  private channel?: Channel
  private stream?: MediaStream
  private context?: AudioContext
  private output?: GainNode
  private microphone?: MediaStreamAudioSourceNode
  private capture?: AudioWorkletNode
  private boost?: GainNode
  private leveler?: DynamicsCompressorNode
  private silent?: GainNode
  private peers = new Map<string, Playback>()
  private presence: Presence = {}
  private id = ""
  private closed = false
  private joined = false
  private muted = true
  private hearing = false
  private talkGeneration = 0
  private volume = 0.8
  private sequence = 0
  private pending = 0
  private quietFrames = 0
  private statsTimer = 0
  private speechTimer = 0
  private update: (peers: VoicePeer[]) => void
  private notice: (message: string) => void
  private ended: () => void
  private speech: (active: boolean) => void
  constructor(update: (peers: VoicePeer[]) => void, notice: (message: string) => void, ended: () => void, speech: (active: boolean) => void) {
    this.update = update; this.notice = notice; this.ended = ended; this.speech = speech
  }

  async join(code: string, deviceId: string) {
    if (!navigator.mediaDevices?.getUserMedia) throw new Error("Mikrofon membutuhkan HTTPS atau localhost.")
    // Resume in the click gesture, before permission/network awaits (mobile autoplay).
    const context = new AudioContext({ sampleRate: 16000, latencyHint: "interactive" })
    this.context = context
    await context.resume()
    const stream = await navigator.mediaDevices.getUserMedia(micConstraints(deviceId))
    if (this.closed) { stream.getTracks().forEach(t => t.stop()); return }
    this.stream = stream
    this.muted = true
    stream.getAudioTracks().forEach(track => { track.enabled = false })
    stream.getAudioTracks()[0].onended = () => this.fail("Mikrofon terputus. Pilih perangkat dan gabung lagi.")
    this.output = context.createGain()
    this.output.gain.value = this.volume
    // Boosted call volume above 100% must not clip into distortion.
    const limiter = context.createDynamicsCompressor()
    limiter.threshold.value = -3
    limiter.knee.value = 6
    limiter.ratio.value = 12
    this.output.connect(limiter).connect(context.destination)
    // Bundle the processor with the app: ngrok's intermediate warning must not
    // replace a separate worklet script fetch with an HTML response.
    const moduleUrl = URL.createObjectURL(new Blob([captureSource], { type: "application/javascript" }))
    try { await context.audioWorklet.addModule(moduleUrl) } finally { URL.revokeObjectURL(moduleUrl) }
    if (this.closed) return
    const [auth, room] = await Promise.all([
      api<{ token: string }>("/api/v1/auth/socket-token", { method: "POST" }),
      api<{ room: { id: string } }>(`/api/v1/rooms/${code}`),
    ])
    if (this.closed) return
    this.socket = new Socket("/socket", { params: () => ({ token: auth.token }), timeout: 30000 })
    this.socket.connect()
    const channel = this.socket.channel(`voice:${room.room.id}`, { transport: "websocket-v2" })
    this.channel = channel
    channel.on("voice.presence", payload => {
      if (this.closed) return
      this.presence = payload.peers as Presence
      for (const [id, peer] of this.peers) if (!this.presence[id]) { this.dispose(peer); this.peers.delete(id) }
      // A held talk button keeps the film silent through pauses between words.
      this.setRemoteTalking(Object.entries(this.presence).some(([id, { metas }]) => id !== this.id && metas.some(meta => meta.muted === false)))
      this.publish()
    })
    channel.on("voice.audio", payload => this.play(String(payload.from), String(payload.pcm), Number(payload.seq)))
    channel.onError(() => this.fail("Koneksi call terputus. Tekan Gabung call untuk menyambung lagi."))
    channel.onClose(() => this.fail("Call berakhir. Anda bisa bergabung kembali jika ruang masih aktif."))
    await new Promise<void>((resolve, reject) => {
      channel.join().receive("ok", payload => {
        this.id = String(payload.peer_id)
        this.joined = true
        this.muted = true
        this.channel?.push("voice.mute", { muted: true })
        this.publish()
        resolve()
      }).receive("error", error => reject(new Error(String(error.message || "Call ditolak."))))
        .receive("timeout", () => reject(new Error("Call tidak merespons. Coba lagi.")))
    })
    if (this.closed) return
    this.microphone = context.createMediaStreamSource(stream)
    this.capture = new AudioWorkletNode(context, "nobarsync-voice-capture", { numberOfInputs: 1, numberOfOutputs: 1, channelCount: 1 })
    this.silent = context.createGain()
    this.silent.gain.value = 0
    // Speech sits far below mastered film audio; lift it before 8-bit mu-law
    // so the call is loud without the listener boosting quantization noise.
    this.boost = context.createGain()
    this.boost.gain.value = 3
    this.leveler = context.createDynamicsCompressor()
    this.leveler.threshold.value = -20
    this.leveler.knee.value = 10
    this.leveler.ratio.value = 6
    this.leveler.attack.value = 0.005
    this.leveler.release.value = 0.15
    this.microphone.connect(this.boost)
    this.boost.connect(this.leveler).connect(this.capture)
    this.capture.connect(this.silent).connect(context.destination)
    this.capture.port.onmessage = event => this.send(event.data as ArrayBuffer)
    let paused = false
    context.onstatechange = () => {
      if (this.closed) return
      if (context.state === "suspended") { paused = true; this.notice("Audio call dijeda browser. Ketuk di mana saja pada halaman untuk melanjutkan.") }
      else if (context.state === "running" && paused) { paused = false; this.notice("") }
    }
    this.statsTimer = window.setInterval(() => this.publish(), 1000)
  }

  private send(frame: ArrayBuffer) {
    if (this.closed || !this.joined || this.muted || this.pending >= 4 || frame.byteLength !== 2560) return
    const samples = new Int16Array(frame)
    let energy = 0
    for (const sample of samples) energy += sample * sample
    // Silence suppression saves bandwidth; one quiet frame/second keeps playout live.
    if (energy / samples.length < SILENCE_POWER) { if (++this.quietFrames < 12) return }
    this.quietFrames = 0
    // Mu-law companding halves transport bandwidth while preserving speech range.
    const bytes = new Uint8Array(samples.length)
    for (let i = 0; i < samples.length; i++) {
      const sign = samples[i] < 0 ? 0x80 : 0
      const value = Math.min(32635, Math.abs(samples[i])) + 0x84
      const exponent = Math.max(0, Math.min(7, Math.floor(Math.log2(value)) - 7))
      bytes[i] = ~(sign | (exponent << 4) | ((value >> (exponent + 3)) & 0x0f)) & 0xff
    }
    const pcm = btoa(String.fromCharCode(...bytes))
    this.pending++
    const finish = () => { this.pending = Math.max(0, this.pending - 1) }
    this.channel?.push("voice.audio", { pcm, seq: this.sequence++ }).receive("ok", finish)
      .receive("error", () => { finish(); this.fail("Server menolak audio call. Keluar lalu gabung kembali.") })
      .receive("timeout", () => { finish(); this.fail("Jaringan call terlalu lambat. Coba gabung kembali.") })
  }

  private play(id: string, pcm: string, sequence: number) {
    const context = this.context
    if (this.closed || id === this.id || !context || !this.output || pcm.length !== 1708 || !Number.isSafeInteger(sequence)) return
    let peer = this.peers.get(id)
    if (!peer) { peer = { next: 0, frames: 0, sequence: -1, sources: new Set() }; this.peers.set(id, peer) }
    if (sequence <= peer.sequence) return
    peer.sequence = sequence
    let bytes: string
    try { bytes = atob(pcm) } catch { return }
    if (bytes.length !== 1280) return
    peer.frames++
    const buffer = context.createBuffer(1, 1280, 16000)
    const output = buffer.getChannelData(0)
    for (let i = 0; i < output.length; i++) {
      const value = ~bytes.charCodeAt(i) & 0xff
      const magnitude = (((value & 0x0f) << 3) + 0x84) << ((value & 0x70) >> 4)
      output[i] = (value & 0x80 ? 0x84 - magnitude : magnitude - 0x84) / 32768
    }
    // Do not accumulate audio while the phone/browser suspends its audio device.
    if (context.state !== "running") { this.dispose(peer); return }
    // Bounded jitter buffer: discard backlog after a TCP/network stall.
    if (peer.next > context.currentTime + 0.45) this.dispose(peer)
    const source = context.createBufferSource()
    source.buffer = buffer
    source.connect(this.output)
    peer.sources.add(source)
    source.onended = () => { peer!.sources.delete(source); source.disconnect() }
    const start = Math.max(peer.next, context.currentTime + 0.12)
    source.start(start)
    peer.next = start + buffer.duration
  }
  private publish() {
    if (this.closed) return
    this.update(Object.entries(this.presence).map(([id, { metas }]) => ({
      id, name: `${metas[0]?.display_name || "Penonton"}${id === this.id ? " (Anda)" : ""}`,
      muted: metas[0]?.muted || false,
      state: this.joined ? "connected" : "new",
      receivedFrames: this.peers.get(id)?.frames || 0,
    })))
  }
  transmit(open: boolean) {
    if (this.closed || !this.joined) return
    const generation = ++this.talkGeneration
    // Unmute is queued before any captured frame, so the server accepts speech
    // from the start of the press instead of after a round-trip plus a delay.
    this.muted = !open
    this.armMic(open)
    const push = this.channel?.push("voice.mute", { muted: !open })
    if (!open) return
    push?.receive("error", () => this.transmitFailed(generation))
      .receive("timeout", () => this.transmitFailed(generation))
  }
  async setDevice(deviceId: string) {
    const context = this.context
    if (this.closed || !context || !this.boost) return
    const stream = await navigator.mediaDevices.getUserMedia(micConstraints(deviceId))
    if (this.closed || !this.boost) { stream.getTracks().forEach(track => track.stop()); return }
    const previous = this.stream
    this.stream = stream
    this.armMic(!this.muted)
    stream.getAudioTracks()[0].onended = () => this.fail("Mikrofon terputus. Pilih perangkat dan gabung lagi.")
    this.microphone?.disconnect()
    this.microphone = context.createMediaStreamSource(stream)
    this.microphone.connect(this.boost)
    previous?.getTracks().forEach(track => { track.onended = null; track.stop() })
  }
  setVolume(value: number) { this.volume = value; if (this.output) this.output.gain.value = value }
  resumeAudio() { void this.context?.resume().catch(() => this.notice("Browser masih memblokir audio call.")) }
  private armMic(enabled: boolean) { this.stream?.getAudioTracks().forEach(track => { track.enabled = enabled }) }
  private transmitFailed(generation: number) {
    if (this.closed || generation !== this.talkGeneration) return
    this.muted = true
    this.armMic(false)
    this.notice("Mikrofon belum terbuka. Tahan tombol bicara lagi.")
  }
  private setRemoteTalking(active: boolean) {
    if (this.closed) return
    window.clearTimeout(this.speechTimer)
    if (active) {
      if (!this.hearing) { this.hearing = true; this.speech(true) }
      return
    }
    if (!this.hearing) return
    // Release after the last buffered words have played out.
    const now = this.context?.currentTime || 0
    let tail = 0
    for (const peer of this.peers.values()) tail = Math.max(tail, peer.next - now)
    this.speechTimer = window.setTimeout(() => {
      this.hearing = false
      if (!this.closed) this.speech(false)
    }, SPEECH_HANGOVER_MS + Math.max(0, tail) * 1000)
  }
  private silenceSpeech() {
    window.clearTimeout(this.speechTimer)
    if (!this.hearing) return
    this.hearing = false
    this.speech(false)
  }
  private dispose(peer: Playback) { peer.sources.forEach(source => { source.onended = null; source.stop(); source.disconnect() }); peer.sources.clear(); peer.next = 0 }
  private fail(message: string) { if (!this.closed) { this.close(); this.notice(message); this.ended() } }
  close() {
    if (this.closed) return
    this.closed = true
    this.joined = false
    this.talkGeneration++
    this.silenceSpeech()
    window.clearInterval(this.statsTimer)
    if (this.capture) { this.capture.port.onmessage = null; this.capture.port.close(); this.capture.disconnect() }
    this.microphone?.disconnect(); this.boost?.disconnect(); this.leveler?.disconnect(); this.silent?.disconnect()
    this.stream?.getTracks().forEach(track => { track.onended = null; track.stop() })
    this.peers.forEach(peer => this.dispose(peer)); this.peers.clear()
    this.output?.disconnect()
    if (this.context) { this.context.onstatechange = null; void this.context.close().catch(() => {}) }
    this.channel?.leave(); this.socket?.disconnect()
  }
}
