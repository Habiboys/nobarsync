import { describe, expect, it } from "vitest"
import { authorizePath, canonical, signToken, verifyToken } from "./token"
import { handleRequest } from "./index"

const claims = {
  exp: 2_000_000_000,
  media_id: "11111111-1111-1111-1111-111111111111",
  prefix: "videos/11111111-1111-1111-1111-111111111111/",
  room_id: "22222222-2222-2222-2222-222222222222",
  scope: "playback",
}

describe("playback token", () => {
  it("uses the canonical payload shared with the API", () => {
    expect(canonical(claims)).toBe(
      '{"exp":2000000000,"media_id":"11111111-1111-1111-1111-111111111111","prefix":"videos/11111111-1111-1111-1111-111111111111/","room_id":"22222222-2222-2222-2222-222222222222","scope":"playback"}',
    )
  })

  it("round-trips and rejects another prefix", async () => {
    const token = await signToken(claims, "test-secret")
    const verified = await verifyToken(token, "test-secret", 1_900_000_000)
    expect(verified.ok).toBe(true)
    if (verified.ok) {
      expect(authorizePath(verified.claims, `${claims.prefix}hls/master.m3u8`)).toBe(true)
      expect(authorizePath(verified.claims, "videos/other/hls/master.m3u8")).toBe(false)
      expect(authorizePath(verified.claims, `${claims.prefix}../secret`)).toBe(false)
    }
  })
})

describe("worker", () => {
  it("serves an authorized object and hides the token from the cache key", async () => {
    const token = await signToken(claims, "test-secret")
    const seen: string[] = []
    const env = {
      MEDIA_TOKEN_SECRET: "test-secret",
      MEDIA: {
        async get(key: string) {
          seen.push(key)
          return { body: new Response("segment").body, size: 7, httpMetadata: { contentType: "video/mp4" } }
        },
      },
    }
    const response = await handleRequest(new Request(`https://media.example/t/${token}/${claims.prefix}hls/480p/segment_00001.m4s`), env)
    expect(response.status).toBe(200)
    expect(seen).toEqual([`${claims.prefix}hls/480p/segment_00001.m4s`])
    const denied = await handleRequest(new Request("https://media.example/t/bad/videos/a/hls/master.m3u8"), env)
    expect(denied.status).toBe(403)
  })
})
