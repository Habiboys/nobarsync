import { describe, expect, it } from "vitest"
import { correctDrift, estimateOffset, targetPosition, viewerFollow } from "./sync"

describe("clock offset", () => {
  it("uses the lowest rtt sample and the midpoint", () => {
    const result = estimateOffset([
      { t0: 0, server: 10_000, t1: 100 },
      { t0: 200, server: 10_240, t1: 240 },
    ])
    expect(result.rtt).toBe(40)
    expect(result.offset).toBe(10_020)
  })
})

describe("timeline", () => {
  it("keeps the old state until effective_at", () => {
    const snapshot = {
      revision: 2,
      media_id: "m",
      duration_ms: 10_000,
      effective_at_ms: 5_000,
      state: {
        status: "paused" as const,
        anchor_position_ms: 1000,
        anchor_server_time_ms: 0,
        playback_rate: 1,
      },
      pending: {
        status: "playing" as const,
        anchor_position_ms: 1000,
        anchor_server_time_ms: 5_000,
        playback_rate: 1,
      },
    }
    expect(targetPosition(snapshot, 4_000)).toBe(1000)
    expect(targetPosition(snapshot, 6_500)).toBe(2500)
  })
})

describe("viewer follow", () => {
  it("slows a viewer who gets ahead and does not speed them past the host", () => {
    expect(viewerFollow({ actualMs: 5_200, hostMs: 5_000, playing: true }).rate).toBe(0.9)
    expect(viewerFollow({ actualMs: 5_200, hostMs: 5_000, playing: true }).seek).toBe(false)
    expect(viewerFollow({ actualMs: 4_700, hostMs: 5_000, playing: true }).rate).toBe(1)
    expect(viewerFollow({ actualMs: 8_000, hostMs: 5_000, playing: true }).seek).toBe(true)
    expect(viewerFollow({ actualMs: 5_400, hostMs: 5_000, playing: false }).positionMs).toBe(5_000)
  })
})

describe("drift", () => {
  it("ignores small drift, nudges medium drift, and seeks large drift after cooldown", () => {
    expect(correctDrift({ driftMs: 80, buffering: false, canSeek: true, lastSeekAt: 0, now: 5000, correcting: false }).rate).toBe(1)
    expect(correctDrift({ driftMs: -600, buffering: false, canSeek: true, lastSeekAt: 0, now: 5000, correcting: false }).rate).toBe(1.04)
    expect(correctDrift({ driftMs: 4000, buffering: true, canSeek: true, lastSeekAt: 0, now: 5000, correcting: false }).type).toBe("none")
    expect(correctDrift({ driftMs: 4000, buffering: false, canSeek: true, lastSeekAt: 4000, now: 5000, correcting: false }).type).toBe("none")
    expect(correctDrift({ driftMs: 4000, buffering: false, canSeek: true, lastSeekAt: 0, now: 5000, correcting: false }).type).toBe("seek")
  })
})
