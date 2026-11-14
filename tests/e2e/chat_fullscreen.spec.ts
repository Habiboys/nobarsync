import { expect, test, type Page } from "@playwright/test"

async function post(page: Page, path: string, body: object) {
  return page.evaluate(
    async ({ path, body }) => {
      const csrf = decodeURIComponent(
        document.cookie.match(/(?:^|; )nobarsync_csrf=([^;]+)/)?.[1] || "",
      )
      const response = await fetch(`/api/v1${path}`, {
        method: "POST",
        headers: {
          "content-type": "application/json",
          "x-nobarsync-csrf": csrf,
        },
        body: JSON.stringify(body),
      })
      if (!response.ok) throw new Error(`HTTP ${response.status}: ${await response.text()}`)
      return response.json()
    },
    { path, body },
  )
}

async function isAtBottom(page: Page) {
  return page.locator(".chat-messages").evaluate((el) => {
    return el.scrollHeight - el.scrollTop - el.clientHeight <= 4
  })
}

test("PC fullscreen controls auto-hide with chat open, chat auto-scrolls and jumps to latest, and message actions work", async ({
  browser,
}) => {
  test.setTimeout(120_000)
  const hostCtx = await browser.newContext({ viewport: { width: 1280, height: 800 } })
  const guestCtx = await browser.newContext({ viewport: { width: 1280, height: 800 } })
  const host = await hostCtx.newPage()
  const guest = await guestCtx.newPage()
  const errors: string[] = []
  host.on("pageerror", (err) => errors.push(err.message))
  guest.on("pageerror", (err) => errors.push(err.message))
  let code = ""

  try {
    await host.goto("/")
    await post(host, "/auth/register", {
      display_name: "Host Chat",
      email: `host-chat-${Date.now()}@example.com`,
      password: "password123",
    })
    await guest.goto("/")
    await post(guest, "/auth/register", {
      display_name: "Tamu Chat",
      email: `guest-chat-${Date.now()}@example.com`,
      password: "password123",
    })

    const film = (
      await post(host, "/media/youtube", {
        title: "Film Chat Fullscreen",
        url: "https://www.youtube.com/watch?v=aqz-KE-bpKQ",
      })
    ).media
    code = (
      await post(host, "/rooms", {
        title: "Ruang Chat Lengkap",
        visibility: "public",
        media_id: film.id,
      })
    ).room.code

    await host.goto(`/watch/${code}`)
    await guest.goto(`/watch/${code}`)
    await expect(host.getByRole("heading", { name: "Film Chat Fullscreen", exact: true })).toBeVisible({
      timeout: 30_000,
    })
    await expect(guest.getByRole("heading", { name: "Film Chat Fullscreen", exact: true })).toBeVisible({
      timeout: 30_000,
    })

    // Seed enough messages to create scrollable history.
    const hostInput = host.getByLabel("Pesan chat", { exact: true })
    const hostSend = host.getByRole("button", { name: "Kirim pesan", exact: true })
    for (let i = 1; i <= 24; i++) {
      await hostInput.fill(`Pesan riwayat ke-${i}`)
      await hostSend.click()
    }
    await expect(guest.getByRole("log").getByText("Pesan riwayat ke-24", { exact: true })).toBeVisible()

    // 1. Incoming messages auto-scroll when pinned at bottom.
    await guest.getByLabel("Pesan chat", { exact: true }).fill("Pesan baru otomatis bawah")
    await guest.getByRole("button", { name: "Kirim pesan", exact: true }).click()
    await expect(host.getByRole("log").getByText("Pesan baru otomatis bawah", { exact: true })).toBeVisible()
    await expect.poll(() => isAtBottom(host)).toBe(true)

    // 2. Opening chat from collapsed state jumps straight to latest messages.
    await host.locator(".chat-messages").evaluate((el) => {
      el.scrollTop = 0
    })
    await host.locator(".player-controls").getByRole("button", { name: "Sembunyikan chat" }).click()
    await host.locator(".player-controls").getByRole("button", { name: "Tampilkan chat" }).click()
    await expect.poll(() => isAtBottom(host)).toBe(true)

    // 3. Entering fullscreen on PC lands on latest messages AND auto-hides video controls even with chat open.
    await host.locator(".chat-messages").evaluate((el) => {
      el.scrollTop = 0
    })
    await host.locator(".player-controls").getByRole("button", { name: "Layar penuh" }).click()
    await expect.poll(() => host.evaluate(() => Boolean(document.fullscreenElement))).toBe(true)
    await expect.poll(() => isAtBottom(host)).toBe(true)

    // Move pointer to top-left of video canvas away from bottom controls so controls go idle after 2.5s.
    await host.mouse.move(240, 240)
    await expect(host.locator(".cinema-player")).toHaveClass(/controls-idle/, { timeout: 6000 })
    await expect(host.locator(".player-controls")).toHaveCSS("opacity", "0")

    // Moving pointer inside chat dock keeps video controls hidden.
    await host.getByLabel("Pesan chat", { exact: true }).click()
    await host.waitForTimeout(300)
    await expect(host.locator(".cinema-player")).toHaveClass(/controls-idle/)

    // Moving pointer back onto video wakes controls.
    await host.mouse.move(320, 320)
    await expect(host.locator(".cinema-player")).not.toHaveClass(/controls-idle/)

    // 4. Full chat actions while still in fullscreen (must not exit fullscreen!).
    // Reply to guest message
    const guestRow = host.locator(".chat-row", { hasText: "Pesan baru otomatis bawah" })
    await guestRow.getByRole("button", { name: /Tindakan pesan/ }).click()
    await host.getByRole("menuitem", { name: "Balas", exact: true }).click()
    await hostInput.fill("Siap, balasan masuk!")
    await hostSend.click()
    await expect(host.getByRole("log").getByText("Siap, balasan masuk!", { exact: true })).toBeVisible()
    await expect(guest.getByRole("log").getByText("Siap, balasan masuk!", { exact: true })).toBeVisible()

    // Edit own reply
    const ownReplyRow = host.locator(".chat-row", { hasText: "Siap, balasan masuk!" })
    await ownReplyRow.getByRole("button", { name: /Tindakan pesan/ }).click()
    await host.getByRole("menuitem", { name: "Edit", exact: true }).click()
    await hostInput.fill("Balasan sudah diedit")
    await host.getByRole("button", { name: "Simpan editan", exact: true }).click()
    await expect(guest.getByRole("log").getByText("Balasan sudah diedit", { exact: true })).toBeVisible()
    await expect(guest.locator(".chat-row", { hasText: "Balasan sudah diedit" })).toContainText("Diedit")

    // React to message
    await ownReplyRow.getByRole("button", { name: /Tindakan pesan/ }).click()
    await host.getByRole("button", { name: "Beri reaksi 👍", exact: true }).click()
    await expect(guest.locator(".chat-react-chip", { hasText: "👍" })).toContainText("1")

    // Pin message
    await ownReplyRow.getByRole("button", { name: /Tindakan pesan/ }).click()
    await host.getByRole("menuitem", { name: "Sematkan", exact: true }).click()
    await expect(guest.locator(".chat-pinned-bar")).toContainText("Balasan sudah diedit")

    // Delete message via inline confirmation (without leaving fullscreen!)
    await ownReplyRow.getByRole("button", { name: /Tindakan pesan/ }).click()
    await host.getByRole("menuitem", { name: "Hapus", exact: true }).click()
    await host.getByRole("button", { name: "Ya, hapus", exact: true }).click()
    await expect(host.getByRole("log").getByText("Balasan sudah diedit", { exact: true })).toHaveCount(0)
    await expect(guest.getByRole("log").getByText("Balasan sudah diedit", { exact: true })).toHaveCount(0)
    await expect(guest.locator(".chat-pinned-bar")).toHaveCount(0)
    expect(await host.evaluate(() => Boolean(document.fullscreenElement))).toBe(true)

    // Scroll up in fullscreen, then exit fullscreen -> must land straight on latest message.
    await host.locator(".chat-messages").evaluate((el) => {
      el.scrollTop = 0
    })
    await host.mouse.move(340, 340)
    await host.locator(".player-controls").getByRole("button", { name: "Keluar layar penuh" }).click()
    await expect.poll(() => host.evaluate(() => Boolean(document.fullscreenElement))).toBe(false)
    await expect.poll(() => isAtBottom(host)).toBe(true)

    expect(errors).toEqual([])
  } finally {
    if (code) await post(host, `/rooms/${code}/close`, {}).catch(() => {})
    await Promise.all([hostCtx.close(), guestCtx.close()])
  }
})
