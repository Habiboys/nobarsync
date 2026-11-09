import { chromium } from "@playwright/test"

const base = process.env.E2E_BASE_URL || "http://127.0.0.1:5178"
const browser = await chromium.launch({
  headless: true,
  args: ["--use-fake-device-for-media-stream", "--use-fake-ui-for-media-stream", "--autoplay-policy=no-user-gesture-required"],
})
const contexts = await Promise.all([0, 1].map(() => browser.newContext({ permissions: ["microphone"] })))
const pages = await Promise.all(contexts.map((context) => context.newPage()))
const [host, guest] = pages

async function post(page, path, body) {
  return page.evaluate(async ({ path, body }) => {
    const csrf = document.cookie.match(/(?:^|; )nobarsync_csrf=([^;]+)/)?.[1] || ""
    const response = await fetch(`/api/v1${path}`, {
      method: "POST",
      headers: { "content-type": "application/json", "x-nobarsync-csrf": decodeURIComponent(csrf) },
      body: JSON.stringify(body),
    })
    if (!response.ok) throw new Error(await response.text())
    return response.json()
  }, { path, body })
}

for (const [i, page] of pages.entries()) {
  await page.addInitScript(() => {
    const log = []
    window.__holdLog = log
    window.__tracks = []
    const original = navigator.mediaDevices.getUserMedia.bind(navigator.mediaDevices)
    navigator.mediaDevices.getUserMedia = async (constraints) => {
      const stream = await original(constraints)
      window.__tracks.push(stream.getAudioTracks()[0])
      return stream
    }
    window.addEventListener("blur", () => log.push("winblur"))
    setInterval(() => {
      const button = document.querySelector(".talk-button")
      if (!button || button.dataset.watched) return
      button.dataset.watched = "1"
      for (const type of ["pointerdown", "pointerup", "pointerleave", "pointerout", "pointercancel", "blur", "lostpointercapture"]) {
        button.addEventListener(type, () => log.push(type + ":" + button.getAttribute("aria-pressed") + ":" + button.textContent), true)
      }
    }, 50)
  })
  await page.goto(base + "/")
  await post(page, "/auth/register", { display_name: `Hold ${i}`, email: `hold-${Date.now()}-${i}@example.com`, password: "password123" })
}
const code = (await post(host, "/rooms", { title: "Hold repro", visibility: "private" })).room.code
await post(guest, `/rooms/${code}/join`, {})
for (const page of pages) {
  await page.goto(base + `/watch/${code}`)
  await page.getByRole("button", { name: "Gabung call", exact: true }).click()
  await page.getByRole("button", { name: "Tahan untuk bicara" }).waitFor({ timeout: 20000 })
}
const button = host.getByRole("button", { name: "Tahan untuk bicara" })
await button.hover()
await host.mouse.down()
await host.waitForTimeout(120)
const mid = await host.evaluate(() => ({
  log: window.__holdLog,
  pressed: document.querySelector(".talk-button")?.getAttribute("aria-pressed"),
  text: document.querySelector(".talk-button")?.textContent,
  enabled: document.querySelector(".talk-button") ? true : false,
  status: document.querySelector(".voice-panel [role=status]")?.textContent,
}))
const track = await host.evaluate(() => window.__tracks.map((track) => track.enabled))
await host.mouse.up()
await host.waitForTimeout(200)
const guestFrames = await guest.locator(".voice-person").filter({ hasNotText: "(Anda)" }).getAttribute("data-received-frames")
const after = await host.evaluate(() => window.__holdLog)
console.log(JSON.stringify({ mid, track, guestFrames, after }, null, 2))
await post(host, `/rooms/${code}/close`, {}).catch(() => {})
await browser.close()
