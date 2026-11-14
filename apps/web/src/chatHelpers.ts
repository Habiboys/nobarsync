export function canDeleteChatMessage(
  role: string,
  authorRole: string | null | undefined,
  isMine: boolean,
): boolean {
  if (isMine) return true
  if (role === "host") return true
  if (role === "moderator") return authorRole !== "host"
  return false
}

export function shouldAutoHideControls({
  fullscreen,
  hasFrame,
  chatOpen,
  isNarrowFullscreen,
}: {
  fullscreen: boolean
  hasFrame: boolean
  chatOpen: boolean
  isNarrowFullscreen: boolean
}): boolean {
  if (!fullscreen || !hasFrame) return false
  if (isNarrowFullscreen && chatOpen) return false
  return true
}

export function isNearBottom({
  scrollHeight,
  scrollTop,
  clientHeight,
  threshold = 36,
}: {
  scrollHeight: number
  scrollTop: number
  clientHeight: number
  threshold?: number
}): boolean {
  return scrollHeight - scrollTop - clientHeight <= threshold
}

export function computePrependScrollTop({
  prevScrollTop,
  prevScrollHeight,
  nextScrollHeight,
}: {
  prevScrollTop: number
  prevScrollHeight: number
  nextScrollHeight: number
}): number {
  return Math.max(0, prevScrollTop + (nextScrollHeight - prevScrollHeight))
}

export type MessageScrollDecision =
  | { action: "preserve-prepend" }
  | { action: "keep-bottom" }
  | { action: "auto-scroll" }
  | { action: "mark-unread" }
  | { action: "none" }

export function decideScrollOnMessagesChange({
  firstId,
  lastId,
  count,
  prevFirstId,
  prevLastId,
  prevCount,
  hasPrependSnapshot,
  wasPinned,
  latestIsMine,
}: {
  firstId?: string
  lastId?: string
  count: number
  prevFirstId?: string
  prevLastId?: string
  prevCount: number
  hasPrependSnapshot: boolean
  wasPinned: boolean
  latestIsMine: boolean
}): MessageScrollDecision {
  if (hasPrependSnapshot && firstId && firstId !== prevFirstId) {
    return { action: "preserve-prepend" }
  }
  if (!lastId) return { action: "none" }
  if (lastId === prevLastId) {
    return wasPinned ? { action: "keep-bottom" } : { action: "none" }
  }
  const appended = count >= prevCount
  if (!appended) return { action: "none" }
  if (wasPinned || latestIsMine || !prevLastId) {
    return { action: "auto-scroll" }
  }
  return { action: "mark-unread" }
}

export function formatTypingSummary(names: string[]): string {
  if (!names.length) return ""
  if (names.length === 1) return `${names[0]} sedang mengetik…`
  if (names.length === 2) return `${names[0]} dan ${names[1]} sedang mengetik…`
  return `${names.length} orang sedang mengetik…`
}

export function formatChatError(error: { code?: unknown; message?: unknown }): string {
  const errorCode = String(error?.code || "")
  if (errorCode === "forbidden") return "Tidak memiliki izin untuk tindakan ini."
  if (errorCode === "not_found") return "Pesan tidak ditemukan."
  if (errorCode === "invalid") return "Pesan tidak valid atau terlalu panjang."
  if (error?.message) return String(error.message)
  return "Permintaan chat ditolak."
}
