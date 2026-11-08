export type ClockSample = { t0: number; server: number; t1: number }

export function estimateOffset(samples: ClockSample[]) {
  if (samples.length === 0) return { offset: 0, rtt: 0 }
  const best = [...samples].sort((a, b) => a.t1 - a.t0 - (b.t1 - b.t0))[0]
  const rtt = best.t1 - best.t0
  const offset = best.server - (best.t0 + rtt / 2)
  return { offset, rtt }
}

export type PlaybackSlice = {
  countdown?: boolean
  kind?: string
  status: "playing" | "paused" | "idle" | "ended"
  anchor_position_ms: number
  anchor_server_time_ms: number
  playback_rate: number
  media_id?: string | null
  duration_ms?: number
}

export type Snapshot = {
  revision: number
  media_id: string | null
  duration_ms: number
  effective_at_ms: number
  control_mode?: string
  state: PlaybackSlice
  pending: PlaybackSlice | null
}

export function clamp(value: number, min: number, max: number) {
  return Math.min(max, Math.max(min, value))
}

export function targetPosition(snapshot: Snapshot, serverNow: number) {
  const pending = snapshot.pending
  const usePending = Boolean(pending) && serverNow >= snapshot.effective_at_ms
  const active = usePending && pending ? pending : snapshot.state
  const duration = (usePending && pending?.duration_ms) || snapshot.duration_ms || 0
  const upper = duration > 0 ? duration : 86_400_000
  if (active.status === "playing") {
    const elapsed = serverNow - active.anchor_server_time_ms
    return clamp(active.anchor_position_ms + elapsed * (active.playback_rate || 1), 0, upper)
  }
  if (active.status === "ended") return upper
  return clamp(active.anchor_position_ms, 0, upper)
}

export type DriftInput = {
  driftMs: number
  buffering: boolean
  canSeek: boolean
  lastSeekAt: number
  now: number
  correcting: boolean
  cooldownMs?: number
}

export function viewerFollow(input: { actualMs: number; hostMs: number; playing: boolean }) {
  const hostMs = Math.max(0, input.hostMs)
  const ahead = input.actualMs - hostMs
  if (!input.playing) {
    return {
      positionMs: hostMs,
      rate: 1,
      seek: Math.abs(input.actualMs - hostMs) > 180,
      loading: Math.abs(input.actualMs - hostMs) > 1500,
    }
  }
  if (ahead > 800) return { positionMs: hostMs, rate: 1, seek: true, loading: true }
  if (ahead > 30) return { positionMs: hostMs, rate: 0.9, seek: false, loading: false }
  const behind = hostMs - input.actualMs
  if (behind > 2500) return { positionMs: hostMs, rate: 1, seek: true, loading: true }
  if (behind > 450) return { positionMs: hostMs, rate: 1.02, seek: false, loading: false }
  return { positionMs: hostMs, rate: 1, seek: false, loading: false }
}

export function correctDrift(input: DriftInput): { type: "none" | "seek"; rate: number } {
  if (input.buffering) return { type: "none", rate: 1 }
  const abs = Math.abs(input.driftMs)
  const deadband = input.correcting ? 120 : 200
  if (abs <= deadband) return { type: "none", rate: 1 }
  if (abs <= 1500) {
    const rate = input.driftMs > 0 ? 0.97 : 1.04
    return { type: "none", rate }
  }
  const cooldown = input.cooldownMs ?? 3000
  if (!input.canSeek || input.now - input.lastSeekAt < cooldown) return { type: "none", rate: 1 }
  return { type: "seek", rate: 1 }
}
