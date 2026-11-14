import { useEffect, useLayoutEffect, useRef, useState } from "react"
import {
  canDeleteChatMessage,
  computePrependScrollTop,
  decideScrollOnMessagesChange,
  formatTypingSummary,
  isNearBottom,
} from "./chatHelpers"

export type ChatReplyTarget = {
  id: string
  display_name?: string | null
  body: string
  deleted?: boolean
}

export type ChatReactionGroup = {
  emoji: string
  count: number
  member_ids: string[]
}

export type ChatMessage = {
  id: string
  body: string
  display_name: string
  member_id?: string | null
  author_role?: string | null
  inserted_at?: string
  edited_at?: string | null
  pinned_at?: string | null
  reply_to?: ChatReplyTarget | null
  reactions?: ChatReactionGroup[]
}

type PersonBrief = { id: string; display_name: string; role: string }

const MESSAGE_EMOJIS = ["👍", "❤️", "😂", "😮", "🔥", "👏"]
const ROOM_EMOJIS = ["❤️", "😂", "🔥", "😮", "👏"]

export function RoomChat({
  fullscreen,
  connected,
  canChat,
  canControl,
  role,
  currentMemberId,
  people,
  chat,
  hasMore,
  loadingOlder,
  pinnedMessage,
  typingNames,
  draft,
  replyTo,
  editing,
  chatError,
  onDraftChange,
  onReplyToChange,
  onEditingChange,
  onClearError,
  onSend,
  onEdit,
  onDelete,
  onReact,
  onPin,
  onRoomReaction,
  onTyping,
  onLoadOlder,
  onCloseChat,
}: {
  fullscreen: boolean
  connected: boolean
  canChat: boolean
  canControl: boolean
  role: string
  currentMemberId: string
  people: PersonBrief[]
  chat: ChatMessage[]
  hasMore: boolean
  loadingOlder: boolean
  pinnedMessage: ChatMessage | null
  typingNames: string[]
  draft: string
  replyTo: ChatMessage | null
  editing: ChatMessage | null
  chatError: string
  onDraftChange: (value: string) => void
  onReplyToChange: (item: ChatMessage | null) => void
  onEditingChange: (item: ChatMessage | null) => void
  onClearError: () => void
  onSend: (body: string, replyToId?: string) => Promise<boolean>
  onEdit: (id: string, body: string) => Promise<boolean>
  onDelete: (id: string) => Promise<boolean>
  onReact: (id: string, emoji: string) => Promise<boolean>
  onPin: (id: string, pinned: boolean) => Promise<boolean>
  onRoomReaction: (emoji: string) => void
  onTyping: (typing: boolean) => void
  onLoadOlder: () => Promise<boolean>
  onCloseChat: () => void
}) {
  const listRef = useRef<HTMLDivElement>(null)
  const inputRef = useRef<HTMLInputElement>(null)
  const pinnedRef = useRef(true)
  const programmaticRef = useRef(false)
  const lastScrollTopRef = useRef(0)
  const prevFirstIdRef = useRef<string | undefined>(undefined)
  const prevLastIdRef = useRef<string | undefined>(undefined)
  const prevCountRef = useRef(0)
  const prependSnapshotRef = useRef<{ scrollHeight: number; scrollTop: number } | null>(null)
  const highlightTimerRef = useRef(0)
  const feedbackTimerRef = useRef(0)

  const [sending, setSending] = useState(false)
  const [busyMessageId, setBusyMessageId] = useState<string | null>(null)
  const [showScrollDown, setShowScrollDown] = useState(false)
  const [unreadCount, setUnreadCount] = useState(0)
  const [menuId, setMenuId] = useState<string | null>(null)
  const [menuDirection, setMenuDirection] = useState<"up" | "down">("down")
  const [menuBox, setMenuBox] = useState<{ left: number; width: number } | null>(null)
  const [confirmDeleteId, setConfirmDeleteId] = useState<string | null>(null)
  const [highlightedId, setHighlightedId] = useState<string | null>(null)
  const [feedback, setFeedback] = useState("")

  function isOwnMessage(item: ChatMessage) {
    if (item.member_id && currentMemberId) return item.member_id === currentMemberId
    const self = people.find((person) => person.id === currentMemberId)
    return Boolean(self && self.display_name === item.display_name)
  }

  function canDeleteMessage(item: ChatMessage) {
    const senderRole = item.author_role || people.find((p) => p.id === item.member_id)?.role
    return canDeleteChatMessage(role, senderRole, isOwnMessage(item))
  }

  function snapToBottom(behavior: ScrollBehavior = "auto") {
    const el = listRef.current
    if (!el) return
    programmaticRef.current = true
    if (behavior === "auto") {
      el.scrollTop = el.scrollHeight
    } else {
      el.scrollTo({ top: el.scrollHeight, behavior })
    }
    lastScrollTopRef.current = el.scrollTop
    pinnedRef.current = true
    setShowScrollDown(false)
    setUnreadCount(0)
    window.requestAnimationFrame(() => {
      const current = listRef.current
      if (current && pinnedRef.current && behavior === "auto") {
        current.scrollTop = current.scrollHeight
        lastScrollTopRef.current = current.scrollTop
      }
      programmaticRef.current = false
    })
  }

  // Always jump straight to the latest messages when opening chat or toggling fullscreen.
  useLayoutEffect(() => {
    pinnedRef.current = true
    setShowScrollDown(false)
    setUnreadCount(0)
    setMenuId(null)
    setConfirmDeleteId(null)
    snapToBottom("auto")
    const raf1 = window.requestAnimationFrame(() => {
      if (pinnedRef.current) snapToBottom("auto")
    })
    const timer = window.setTimeout(() => {
      if (pinnedRef.current) snapToBottom("auto")
    }, 60)
    return () => {
      window.cancelAnimationFrame(raf1)
      window.clearTimeout(timer)
    }
  }, [fullscreen])

  // Keep pinned at bottom across container resizes (fullscreen layout, reply/edit bar, virtual keyboard).
  useEffect(() => {
    const el = listRef.current
    if (!el || typeof ResizeObserver === "undefined") return
    const observer = new ResizeObserver(() => {
      if (pinnedRef.current) snapToBottom("auto")
    })
    observer.observe(el)
    return () => observer.disconnect()
  }, [])

  // Handle message additions (auto-scroll when pinned or sent by self) and history prepends.
  useLayoutEffect(() => {
    const el = listRef.current
    if (!el) return
    const firstId = chat[0]?.id
    const lastId = chat[chat.length - 1]?.id
    const prevFirstId = prevFirstIdRef.current
    const prevLastId = prevLastIdRef.current
    const prevCount = prevCountRef.current
    prevFirstIdRef.current = firstId
    prevLastIdRef.current = lastId
    prevCountRef.current = chat.length

    const latest = chat[chat.length - 1]
    const decision = decideScrollOnMessagesChange({
      firstId,
      lastId,
      count: chat.length,
      prevFirstId,
      prevLastId,
      prevCount,
      hasPrependSnapshot: Boolean(prependSnapshotRef.current),
      wasPinned: pinnedRef.current,
      latestIsMine: latest ? isOwnMessage(latest) : false,
    })

    if (decision.action === "preserve-prepend" && prependSnapshotRef.current) {
      const { scrollHeight, scrollTop } = prependSnapshotRef.current
      prependSnapshotRef.current = null
      programmaticRef.current = true
      el.scrollTop = computePrependScrollTop({
        prevScrollTop: scrollTop,
        prevScrollHeight: scrollHeight,
        nextScrollHeight: el.scrollHeight,
      })
      lastScrollTopRef.current = el.scrollTop
      window.requestAnimationFrame(() => {
        programmaticRef.current = false
      })
      return
    }
    prependSnapshotRef.current = null

    if (decision.action === "keep-bottom") {
      snapToBottom("auto")
      return
    }
    if (decision.action === "auto-scroll") {
      snapToBottom("auto")
      const raf = window.requestAnimationFrame(() => {
        if (pinnedRef.current) snapToBottom("auto")
      })
      return () => window.cancelAnimationFrame(raf)
    }
    if (decision.action === "mark-unread") {
      setUnreadCount((count) => count + 1)
      setShowScrollDown(true)
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [chat])

  // Close open message menu on outside click or Escape.
  useEffect(() => {
    if (!menuId) return
    const onPointerDown = (event: PointerEvent) => {
      const target = event.target as HTMLElement | null
      if (target?.closest(".chat-msg-actions")) return
      setMenuId(null)
      setConfirmDeleteId(null)
    }
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        event.stopPropagation()
        setMenuId(null)
        setConfirmDeleteId(null)
      }
    }
    document.addEventListener("pointerdown", onPointerDown)
    document.addEventListener("keydown", onKeyDown)
    return () => {
      document.removeEventListener("pointerdown", onPointerDown)
      document.removeEventListener("keydown", onKeyDown)
    }
  }, [menuId])

  useEffect(() => {
    return () => {
      window.clearTimeout(highlightTimerRef.current)
      window.clearTimeout(feedbackTimerRef.current)
    }
  }, [])

  function handleListScroll() {
    const el = listRef.current
    if (!el || programmaticRef.current) return
    if (isNearBottom({ scrollHeight: el.scrollHeight, scrollTop: el.scrollTop, clientHeight: el.clientHeight })) {
      pinnedRef.current = true
      setShowScrollDown(false)
      setUnreadCount(0)
    } else if (el.scrollTop < lastScrollTopRef.current - 4) {
      pinnedRef.current = false
      setShowScrollDown(true)
    }
    lastScrollTopRef.current = el.scrollTop
  }

  function showNotice(text: string) {
    setFeedback(text)
    window.clearTimeout(feedbackTimerRef.current)
    feedbackTimerRef.current = window.setTimeout(() => setFeedback(""), 2200)
  }

  function jumpToMessage(id: string) {
    const target = document.getElementById(`chat-msg-${id}`)
    if (!target) {
      showNotice("Pesan tidak ada di daftar yang dimuat.")
      return
    }
    target.scrollIntoView({ block: "center", behavior: "smooth" })
    setHighlightedId(id)
    window.clearTimeout(highlightTimerRef.current)
    highlightTimerRef.current = window.setTimeout(() => setHighlightedId(null), 1500)
  }

  function openMenu(id: string, trigger: HTMLButtonElement, mine: boolean) {
    if (menuId === id) {
      setMenuId(null)
      setConfirmDeleteId(null)
      return
    }
    const listRect = listRef.current?.getBoundingClientRect()
    const triggerRect = trigger.getBoundingClientRect()
    if (listRect) {
      const spaceBelow = listRect.bottom - triggerRect.bottom
      const spaceAbove = triggerRect.top - listRect.top
      setMenuDirection(spaceBelow < 240 && spaceAbove > spaceBelow ? "up" : "down")
      const width = Math.max(180, Math.min(276, Math.floor(listRect.width - 16)))
      const preferredLeft = mine ? triggerRect.right - width : triggerRect.left
      const clampedLeft = Math.max(
        listRect.left + 8,
        Math.min(preferredLeft, listRect.right - width - 8),
      )
      setMenuBox({ left: Math.round(clampedLeft - triggerRect.left), width })
    } else {
      setMenuDirection("down")
      setMenuBox(null)
    }
    setConfirmDeleteId(null)
    setMenuId(id)
  }

  function startReply(item: ChatMessage) {
    onEditingChange(null)
    onReplyToChange(item)
    onClearError()
    setMenuId(null)
    setConfirmDeleteId(null)
    inputRef.current?.focus()
  }

  function startEdit(item: ChatMessage) {
    onReplyToChange(null)
    onEditingChange(item)
    onDraftChange(item.body)
    onClearError()
    setMenuId(null)
    setConfirmDeleteId(null)
    window.requestAnimationFrame(() => inputRef.current?.focus())
  }

  function cancelComposeMode() {
    if (editing) {
      onEditingChange(null)
      onDraftChange("")
    }
    if (replyTo) {
      onReplyToChange(null)
    }
    onClearError()
  }

  async function handleCopy(item: ChatMessage) {
    setMenuId(null)
    setConfirmDeleteId(null)
    try {
      await navigator.clipboard.writeText(item.body)
      showNotice("Pesan disalin.")
    } catch {
      showNotice("Tidak bisa menyalin di browser ini.")
    }
  }

  async function handleDelete(id: string) {
    setBusyMessageId(id)
    setMenuId(null)
    setConfirmDeleteId(null)
    const ok = await onDelete(id)
    setBusyMessageId(null)
    if (ok) showNotice("Pesan dihapus.")
  }

  async function handleLoadOlderClick() {
    const el = listRef.current
    if (el) prependSnapshotRef.current = { scrollHeight: el.scrollHeight, scrollTop: el.scrollTop }
    const ok = await onLoadOlder()
    if (!ok) prependSnapshotRef.current = null
  }

  async function handleSubmit(event: React.FormEvent) {
    event.preventDefault()
    const text = draft.trim()
    if (!text || sending || !canChat || !connected) return
    onClearError()
    setSending(true)
    onTyping(false)
    if (editing) {
      const ok = await onEdit(editing.id, text)
      setSending(false)
      if (ok) {
        onEditingChange(null)
        onDraftChange("")
      }
      return
    }
    const ok = await onSend(text, replyTo?.id)
    setSending(false)
    if (ok) {
      onDraftChange("")
      onReplyToChange(null)
      snapToBottom("auto")
    }
  }

  const typingText = formatTypingSummary(typingNames)

  return (
    <aside className={fullscreen ? "chat-panel chat-dock" : "chat-panel"} aria-label="Obrolan ruang">
      <div className="chat-heading">
        <div>
          <h2>Obrolan ruang</h2>
        </div>
        <button type="button" className="chat-close-btn" aria-label="Tutup panel chat" onClick={onCloseChat}>
          ✕
        </button>
      </div>

      {pinnedMessage ? (
        <div className="chat-pinned-bar">
          <button
            type="button"
            className="chat-pinned-jump"
            onClick={() => jumpToMessage(pinnedMessage.id)}
            title="Lihat pesan yang disematkan"
          >
            <span className="chat-pinned-label">Disematkan</span>
            <span className="chat-pinned-text">
              <strong>{pinnedMessage.display_name}:</strong> {pinnedMessage.body}
            </span>
          </button>
          {canControl ? (
            <button
              type="button"
              className="chat-pinned-unpin"
              aria-label="Lepas pesan yang disematkan"
              onClick={() => void onPin(pinnedMessage.id, false)}
            >
              Lepas
            </button>
          ) : null}
        </div>
      ) : null}

      <div className="chat-messages-wrap">
        <div
          ref={listRef}
          className="chat-messages"
          role="log"
          aria-label="Pesan ruang"
          aria-live="polite"
          onScroll={handleListScroll}
        >
          {hasMore ? (
            <div className="chat-load-older">
              <button type="button" disabled={loadingOlder} onClick={() => void handleLoadOlderClick()}>
                {loadingOlder ? "Memuat pesan lama…" : "Muat pesan lama"}
              </button>
            </div>
          ) : null}

          {!chat.length ? (
            <div className="chat-empty">
              <h3>Belum ada pesan</h3>
              <p>Sapa teman nonton, balas pesan, atau kirim reaksi untuk mulai mengobrol.</p>
            </div>
          ) : (
            chat.map((item) => {
              const mine = isOwnMessage(item)
              const canDelete = canDeleteMessage(item)
              const isMenuOpen = menuId === item.id
              const isPinned = Boolean(item.pinned_at || pinnedMessage?.id === item.id)
              const sent = item.inserted_at
                ? new Date(item.inserted_at).toLocaleTimeString("id-ID", { hour: "2-digit", minute: "2-digit" })
                : ""
              const reactions = item.reactions || []

              return (
                <div
                  id={`chat-msg-${item.id}`}
                  className={`chat-row${mine ? " mine" : ""}${highlightedId === item.id ? " highlighted" : ""}${isMenuOpen ? " menu-open" : ""}`}
                  key={item.id}
                >
                  <div className="chat-bubble">
                    {item.reply_to ? (
                      item.reply_to.deleted ? (
                        <div className="chat-reply-quote deleted">
                          <span>Pesan asli telah dihapus</span>
                        </div>
                      ) : (
                        <button
                          type="button"
                          className="chat-reply-quote"
                          onClick={() => jumpToMessage(item.reply_to!.id)}
                        >
                          <strong>{item.reply_to.display_name || "Penonton"}</strong>
                          <span>{item.reply_to.body}</span>
                        </button>
                      )
                    ) : null}

                    {mine ? null : <strong>{item.display_name}</strong>}
                    <p>{item.body}</p>

                    {reactions.length ? (
                      <div className="chat-msg-reactions">
                        {reactions.map((group) => {
                          const reacted = Boolean(currentMemberId && group.member_ids.includes(currentMemberId))
                          return (
                            <button
                              key={group.emoji}
                              type="button"
                              className={`chat-react-chip${reacted ? " active" : ""}`}
                              aria-pressed={reacted}
                              aria-label={`Reaksi ${group.emoji}, ${group.count}`}
                              disabled={!connected}
                              onClick={() => void onReact(item.id, group.emoji)}
                            >
                              <span>{group.emoji}</span>
                              <span>{group.count}</span>
                            </button>
                          )
                        })}
                      </div>
                    ) : null}

                    <div className="chat-meta">
                      {isPinned ? <span className="chat-meta-tag">Disematkan</span> : null}
                      {item.edited_at ? <span className="chat-meta-tag">Diedit</span> : null}
                      {sent ? <time>{sent}</time> : null}
                    </div>
                  </div>

                  <div className="chat-msg-actions">
                    <button
                      type="button"
                      className="chat-msg-trigger"
                      aria-haspopup="menu"
                      aria-expanded={isMenuOpen}
                      aria-label={`Tindakan pesan dari ${item.display_name}`}
                      disabled={busyMessageId === item.id}
                      onClick={(event) => openMenu(item.id, event.currentTarget, mine)}
                    >
                      ⋯
                    </button>

                    {isMenuOpen ? (
                      <div
                        className={`chat-msg-menu ${menuDirection === "up" ? "dir-up" : "dir-down"}`}
                        style={menuBox ? { left: `${menuBox.left}px`, width: `${menuBox.width}px` } : undefined}
                        role="menu"
                      >
                        {confirmDeleteId === item.id ? (
                          <div className="chat-delete-confirm">
                            <p>Hapus pesan ini?</p>
                            <div className="chat-delete-actions">
                              <button
                                type="button"
                                className="chat-menu-danger"
                                onClick={() => void handleDelete(item.id)}
                              >
                                Ya, hapus
                              </button>
                              <button
                                type="button"
                                onClick={() => setConfirmDeleteId(null)}
                              >
                                Batal
                              </button>
                            </div>
                          </div>
                        ) : (
                          <>
                            <div className="chat-menu-emojis" aria-label="Reaksi cepat">
                              {MESSAGE_EMOJIS.map((emoji) => (
                                <button
                                  key={emoji}
                                  type="button"
                                  aria-label={`Beri reaksi ${emoji}`}
                                  onClick={() => {
                                    setMenuId(null)
                                    void onReact(item.id, emoji)
                                  }}
                                >
                                  {emoji}
                                </button>
                              ))}
                            </div>
                            {canChat ? (
                              <button type="button" role="menuitem" onClick={() => startReply(item)}>
                                Balas
                              </button>
                            ) : null}
                            {mine && canChat ? (
                              <button type="button" role="menuitem" onClick={() => startEdit(item)}>
                                Edit
                              </button>
                            ) : null}
                            <button type="button" role="menuitem" onClick={() => void handleCopy(item)}>
                              Salin teks
                            </button>
                            {canControl ? (
                              <button
                                type="button"
                                role="menuitem"
                                onClick={() => {
                                  setMenuId(null)
                                  void onPin(item.id, !isPinned)
                                }}
                              >
                                {isPinned ? "Lepas sematan" : "Sematkan"}
                              </button>
                            ) : null}
                            {canDelete ? (
                              <button
                                type="button"
                                role="menuitem"
                                className="chat-menu-danger"
                                onClick={() => setConfirmDeleteId(item.id)}
                              >
                                Hapus
                              </button>
                            ) : null}
                          </>
                        )}
                      </div>
                    ) : null}
                  </div>
                </div>
              )
            })
          )}
        </div>

        {showScrollDown ? (
          <button
            type="button"
            className="chat-jump-latest"
            onClick={() => snapToBottom("smooth")}
          >
            {unreadCount > 0 ? `↓ ${unreadCount} pesan baru` : "↓ Ke pesan terbaru"}
          </button>
        ) : null}
      </div>

      {typingText || feedback || chatError ? (
        <div className="chat-status-line" role={chatError ? "alert" : "status"}>
          {chatError ? <span className="chat-error-text">{chatError}</span> : <span>{feedback || typingText}</span>}
        </div>
      ) : null}

      <div className="emoji-row">
        {ROOM_EMOJIS.map((emoji) => (
          <button key={emoji} type="button" aria-label={`Reaksi ${emoji}`} onClick={() => onRoomReaction(emoji)}>
            {emoji}
          </button>
        ))}
      </div>

      {editing || replyTo ? (
        <div className="chat-compose-banner">
          <div className="chat-compose-copy">
            <strong>{editing ? "Mengedit pesan" : `Membalas ${replyTo?.display_name}`}</strong>
            <span>{editing ? editing.body : replyTo?.body}</span>
          </div>
          <button
            type="button"
            className="chat-compose-cancel"
            aria-label={editing ? "Batal mengedit" : "Batal membalas"}
            onClick={cancelComposeMode}
          >
            ✕
          </button>
        </div>
      ) : null}

      <form className="chat-form" onSubmit={(event) => void handleSubmit(event)}>
        <input
          ref={inputRef}
          aria-label="Pesan chat"
          maxLength={500}
          disabled={!connected || !canChat}
          placeholder={!canChat ? "Chat dibatasi host" : editing ? "Perbarui pesan…" : "Tulis pesan…"}
          value={draft}
          onChange={(event) => {
            onDraftChange(event.target.value)
            onTyping(event.target.value.trim().length > 0)
          }}
          onBlur={() => onTyping(false)}
          onKeyDown={(event) => {
            if (event.key === "Escape" && (editing || replyTo)) {
              event.preventDefault()
              event.stopPropagation()
              cancelComposeMode()
              return
            }
            if (event.key === "ArrowUp" && !draft && !editing && canChat) {
              const latestMine = [...chat].reverse().find((item) => isOwnMessage(item))
              if (latestMine) {
                event.preventDefault()
                startEdit(latestMine)
              }
            }
          }}
        />
        <button
          type="submit"
          disabled={!connected || !canChat || !draft.trim() || sending}
          aria-label={editing ? "Simpan editan" : "Kirim pesan"}
        >
          {editing ? "✓" : "↑"}
        </button>
      </form>
    </aside>
  )
}
