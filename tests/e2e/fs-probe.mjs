import { chromium } from "@playwright/test"

const base = process.env.E2E_BASE_URL || "http://127.0.0.1:5178"
const browser = await chromium.launch({ headless: true, args: ["--autoplay-policy=no-user-gesture-required", "--use-fake-device-for-media-stream", "--use-fake-ui-for-media-stream"] })
const context = await browser.newContext({ viewport: { width: 1440, height: 900 } })
const page = await context.newPage()
async function post(path, body) {
  return page.evaluate(async ({ path, body }) => {
    const csrf = document.cookie.match(/(?:^|; )nobarsync_csrf=([^;]+)/)?.[1] || ""
    const response = await fetch(`/api/v1${path}`, { method: "POST", headers: { "content-type": "application/json", "x-nobarsync-csrf": decodeURIComponent(csrf) }, body: JSON.stringify(body) })
    if (!response.ok) throw new Error(await response.text())
    return response.json()
  }, { path, body })
}
await page.goto(base + "/")
await post("/auth/register", { display_name: "FS probe", email: `fs-${Date.now()}@example.com`, password: "password123" })
const film = (await post("/media/youtube", { title: "FS probe", url: "https://www.youtube.com/watch?v=aqz-KE-bpKQ" })).media
const code = (await post("/rooms", { title: "FS probe", visibility: "private", media_id: film.id })).room.code
await page.goto(base + `/watch/${code}`)
await page.waitForTimeout(4000)
await context.grantPermissions(["microphone"])
const measure = async (label) => {
  const data = await page.evaluate(() => {
    const rect = (el) => { if (!el) return null; const r = el.getBoundingClientRect(); return { x: Math.round(r.x), y: Math.round(r.y), w: Math.round(r.width), h: Math.round(r.height), display: getComputedStyle(el).display } }
    const player = document.querySelector(".cinema-player")
    return {
      fsEl: document.fullscreenElement?.className || null,
      viewport: [innerWidth, innerHeight],
      player: rect(player),
      grid: player && getComputedStyle(player).gridTemplateColumns + " / " + getComputedStyle(player).gridTemplateRows,
      video: rect(player?.querySelector("video")),
      yt: rect(player?.querySelector(".youtube-frame")),
      iframe: rect(player?.querySelector(".youtube-frame iframe")),
      controls: rect(player?.querySelector(".player-controls")),
      chat: rect(player?.querySelector(".chat-dock")),
      talk: rect(player?.querySelector(".talk-button")),
      children: [...(player?.children || [])].map((el) => el.tagName + "." + el.className + " pos=" + getComputedStyle(el).position + " disp=" + getComputedStyle(el).display),
    }
  })
  console.log(label, JSON.stringify(data, null, 1))
}
await page.getByRole("button", { name: "Gabung call", exact: true }).click()
await page.getByRole("button", { name: "Tahan untuk bicara" }).waitFor({ timeout: 20000 })
await page.getByRole("button", { name: "Layar penuh" }).click()
await page.waitForTimeout(1200)
await measure("FS_CHAT_OPEN")
await page.screenshot({ path: "fs-chat-open.png" })
await page.getByRole("button", { name: "Sembunyikan chat" }).first().click()
await page.waitForTimeout(800)
await measure("FS_CHAT_CLOSED")
await page.screenshot({ path: "fs-chat-closed.png" })
await post(`/rooms/${code}/close`, {}).catch(() => {})
await browser.close()
