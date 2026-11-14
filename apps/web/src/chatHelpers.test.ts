import { describe, expect, it } from "vitest"
import {
  canDeleteChatMessage,
  computePrependScrollTop,
  decideScrollOnMessagesChange,
  formatChatError,
  formatTypingSummary,
  isNearBottom,
  shouldAutoHideControls,
} from "./chatHelpers"

describe("shouldAutoHideControls", () => {
  it("allows auto-hide in PC fullscreen even when chat is open", () => {
    expect(
      shouldAutoHideControls({
        fullscreen: true,
        hasFrame: true,
        chatOpen: true,
        isNarrowFullscreen: false,
      }),
    ).toBe(true)
  })

  it("disables auto-hide on narrow fullscreen only while chat covers the video pane", () => {
    expect(
      shouldAutoHideControls({
        fullscreen: true,
        hasFrame: true,
        chatOpen: true,
        isNarrowFullscreen: true,
      }),
    ).toBe(false)
    expect(
      shouldAutoHideControls({
        fullscreen: true,
        hasFrame: true,
        chatOpen: false,
        isNarrowFullscreen: true,
      }),
    ).toBe(true)
  })

  it("never hides outside fullscreen", () => {
    expect(
      shouldAutoHideControls({
        fullscreen: false,
        hasFrame: true,
        chatOpen: false,
        isNarrowFullscreen: false,
      }),
    ).toBe(false)
  })
})

describe("chat scroll helpers", () => {
  it("auto-scrolls when pinned or when current user sends a message", () => {
    expect(
      decideScrollOnMessagesChange({
        firstId: "1",
        lastId: "2",
        count: 2,
        prevFirstId: "1",
        prevLastId: "1",
        prevCount: 1,
        hasPrependSnapshot: false,
        wasPinned: true,
        latestIsMine: false,
      }),
    ).toEqual({ action: "auto-scroll" })

    expect(
      decideScrollOnMessagesChange({
        firstId: "1",
        lastId: "3",
        count: 3,
        prevFirstId: "1",
        prevLastId: "2",
        prevCount: 2,
        hasPrependSnapshot: false,
        wasPinned: false,
        latestIsMine: true,
      }),
    ).toEqual({ action: "auto-scroll" })
  })

  it("marks unread instead of jumping when user scrolled up and another member posts", () => {
    expect(
      decideScrollOnMessagesChange({
        firstId: "1",
        lastId: "4",
        count: 4,
        prevFirstId: "1",
        prevLastId: "3",
        prevCount: 3,
        hasPrependSnapshot: false,
        wasPinned: false,
        latestIsMine: false,
      }),
    ).toEqual({ action: "mark-unread" })
  })

  it("ignores deletion of the last message when unpinned", () => {
    expect(
      decideScrollOnMessagesChange({
        firstId: "1",
        lastId: "2",
        count: 2,
        prevFirstId: "1",
        prevLastId: "3",
        prevCount: 3,
        hasPrependSnapshot: false,
        wasPinned: false,
        latestIsMine: true,
      }),
    ).toEqual({ action: "none" })
  })

  it("preserves reading offset when older messages are prepended", () => {
    expect(
      decideScrollOnMessagesChange({
        firstId: "0",
        lastId: "4",
        count: 5,
        prevFirstId: "1",
        prevLastId: "4",
        prevCount: 4,
        hasPrependSnapshot: true,
        wasPinned: false,
        latestIsMine: false,
      }),
    ).toEqual({ action: "preserve-prepend" })
    expect(
      computePrependScrollTop({
        prevScrollTop: 120,
        prevScrollHeight: 800,
        nextScrollHeight: 1450,
      }),
    ).toBe(770)
  })

  it("detects bottom proximity within threshold", () => {
    expect(isNearBottom({ scrollHeight: 1000, scrollTop: 480, clientHeight: 500 })).toBe(true)
    expect(isNearBottom({ scrollHeight: 1000, scrollTop: 300, clientHeight: 500 })).toBe(false)
  })
})

describe("chat permissions and formatting", () => {
  it("enforces host and moderator deletion rules safely", () => {
    expect(canDeleteChatMessage("viewer", "host", false)).toBe(false)
    expect(canDeleteChatMessage("viewer", "host", true)).toBe(true)
    expect(canDeleteChatMessage("moderator", "viewer", false)).toBe(true)
    expect(canDeleteChatMessage("moderator", "host", false)).toBe(false)
    expect(canDeleteChatMessage("host", "moderator", false)).toBe(true)
  })

  it("formats typing indicators and localized errors", () => {
    expect(formatTypingSummary([])).toBe("")
    expect(formatTypingSummary(["Budi"])).toBe("Budi sedang mengetik…")
    expect(formatTypingSummary(["Budi", "Sari"])).toBe("Budi dan Sari sedang mengetik…")
    expect(formatTypingSummary(["Budi", "Sari", "Rani"])).toBe("3 orang sedang mengetik…")
    expect(formatChatError({ code: "forbidden" })).toBe("Tidak memiliki izin untuk tindakan ini.")
    expect(formatChatError({ code: "not_found" })).toBe("Pesan tidak ditemukan.")
    expect(formatChatError({ code: "invalid" })).toBe("Pesan tidak valid atau terlalu panjang.")
  })
})
