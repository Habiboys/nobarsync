import { authorizePath, verifyToken } from "./token"

type Bucket = {
  get(key: string, options?: { range?: { offset: number; length?: number } }): Promise<{ body: ReadableStream | null; size: number; httpMetadata?: { contentType?: string } } | null>
}

export type Env = { MEDIA: Bucket; MEDIA_TOKEN_SECRET: string }

export async function handleRequest(request: Request, env: Env) {
  const url = new URL(request.url)
  const match = url.pathname.match(/^\/t\/([^/]+)\/(.+)$/)
  if (!request.method.match(/^(GET|HEAD)$/) || !match) return new Response("Not found", { status: 404 })
  const verified = await verifyToken(decodeURIComponent(match[1]), env.MEDIA_TOKEN_SECRET)
  if (!verified.ok) return new Response("Forbidden", { status: 403 })
  const key = match[2]
  if (!authorizePath(verified.claims, key)) return new Response("Forbidden", { status: 403 })
  const range = request.headers.get("range")
  const object = await env.MEDIA.get(key, range ? { range: parseRange(range) } : undefined)
  if (!object) return new Response("Not found", { status: 404 })
  const headers = new Headers({
    "content-type": object.httpMetadata?.contentType || mime(key),
    "cache-control": "public, max-age=3600",
    "accept-ranges": "bytes",
  })
  if (request.method === "HEAD") return new Response(null, { headers })
  return new Response(object.body, { headers })
}

function parseRange(header: string) {
  const match = header.match(/bytes=(\d+)-(\d+)?/)
  if (!match) return undefined
  const offset = Number(match[1])
  const end = match[2] ? Number(match[2]) : undefined
  return { offset, length: end == null ? undefined : end - offset + 1 }
}

function mime(key: string) {
  if (key.endsWith(".m3u8")) return "application/vnd.apple.mpegurl"
  if (key.endsWith(".m4s") || key.endsWith(".mp4")) return "video/mp4"
  if (key.endsWith(".vtt")) return "text/vtt"
  if (key.endsWith(".webp")) return "image/webp"
  return "application/octet-stream"
}

export default { fetch: handleRequest }
