const encoder = new TextEncoder()

export type Claims = {
  exp: number
  media_id: string
  prefix: string
  room_id: string | null
  scope: string
}

export function canonical(claims: Claims) {
  const room = claims.room_id == null ? "null" : `"${claims.room_id}"`
  return `{"exp":${claims.exp},"media_id":"${claims.media_id}","prefix":"${claims.prefix}","room_id":${room},"scope":"${claims.scope}"}`
}

function bytesToBase64Url(bytes: Uint8Array) {
  let text = ""
  bytes.forEach((byte) => { text += String.fromCharCode(byte) })
  return btoa(text).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "")
}

function base64UrlToBytes(value: string) {
  const padded = value.replaceAll("-", "+").replaceAll("_", "/") + "=".repeat((4 - (value.length % 4)) % 4)
  const binary = atob(padded)
  return Uint8Array.from(binary, (char) => char.charCodeAt(0))
}

async function hmac(secret: string, payload: string) {
  const key = await crypto.subtle.importKey("raw", encoder.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"])
  const signature = await crypto.subtle.sign("HMAC", key, encoder.encode(payload))
  return bytesToBase64Url(new Uint8Array(signature))
}

export async function signToken(claims: Claims, secret: string) {
  const payload = bytesToBase64Url(encoder.encode(canonical(claims)))
  return `${payload}.${await hmac(secret, payload)}`
}

export async function verifyToken(token: string, secret: string, now = Date.now() / 1000) {
  const split = token.indexOf(".")
  if (split < 1) return { ok: false as const, reason: "malformed" }
  const payload = token.slice(0, split)
  const signature = token.slice(split + 1)
  const expected = await hmac(secret, payload)
  if (expected.length !== signature.length) return { ok: false as const, reason: "bad_signature" }
  let mismatch = 0
  for (let index = 0; index < expected.length; index += 1) mismatch |= expected.charCodeAt(index) ^ signature.charCodeAt(index)
  if (mismatch !== 0) return { ok: false as const, reason: "bad_signature" }
  const claims = JSON.parse(new TextDecoder().decode(base64UrlToBytes(payload))) as Claims
  if (claims.exp < now) return { ok: false as const, reason: "expired" }
  return { ok: true as const, claims }
}

export function authorizePath(claims: Claims, path: string) {
  if (path.includes("..") || path.includes("\\") || path.includes("\0") || path.startsWith("/")) return false
  return path.startsWith(claims.prefix)
}
