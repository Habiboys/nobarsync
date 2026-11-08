export class ApiError extends Error {
  code: string
  status: number
  constructor(message: string, code = "error", status = 400) {
    super(message)
    this.code = code
    this.status = status
  }
}

function csrf() {
  const match = document.cookie.match(/(?:^|; )nobarsync_csrf=([^;]+)/)
  return match ? decodeURIComponent(match[1]) : ""
}

export async function api<T>(path: string, options: RequestInit = {}): Promise<T> {
  const headers = new Headers(options.headers)
  headers.set("accept", "application/json")
  if (options.body && !(options.body instanceof FormData) && !headers.has("content-type")) {
    headers.set("content-type", "application/json")
  }
  const token = csrf()
  if (token) headers.set("x-nobarsync-csrf", token)
  const response = await fetch(path, { ...options, headers, credentials: "include" })
  const text = await response.text()
  let data: { error?: { message?: string; code?: string; details?: Record<string, string[] | string> } } = {}
  if (text) {
    try {
      data = JSON.parse(text)
    } catch {
      throw new ApiError(`Server mengembalikan halaman HTML (${response.status}). Muat ulang halaman.`, "html", response.status)
    }
  }
  if (!response.ok) {
    const details = data?.error?.details
    const extra = details
      ? Object.entries(details)
          .map(([key, value]) => `${key}: ${Array.isArray(value) ? value.join(", ") : value}`)
          .join("; ")
      : ""
    const message = [data?.error?.message || response.statusText, extra].filter(Boolean).join(" — ")
    throw new ApiError(message, data?.error?.code || "error", response.status)
  }
  return data as T
}

export type User = { id: string; email: string; display_name: string; role: string; avatar_key?: string | null }
export type Guest = { id: string; display_name: string }
export type Media = {
  id: string
  title: string
  status: string
  provider: string
  duration_ms: number | null
  poster_key: string | null
  progress: number
  error: string | null
  visibility: string
  owner_id?: string
  youtube_id?: string | null
  variants: { label: string; height: number | null }[]
  subtitles: { language: string; label: string }[]
}
export type Room = {
  id: string
  code: string
  title: string
  visibility: string
  max_viewers: number
  control_mode: string
  buffering_mode: string
  chat_permission: string
  locked: boolean
  status: string
  media_id: string | null
  host_user_id: string | null
}
export type Member = { id: string; display_name: string; role: string; user_id: string | null }
