import { test, expect, type Page } from "@playwright/test"

async function holdTalk(page: Page, down: boolean) {
  await page.getByRole("button", { name: "Tahan untuk bicara" }).evaluate((el, down) => {
    el.dispatchEvent(new PointerEvent(down ? "pointerdown" : "pointerup", { bubbles: true, cancelable: true, pointerId: 1, isPrimary: true, pointerType: "mouse" }))
  }, down)
}

async function post(page: Page, path: string, body: object) {
  return page.evaluate(async ({ path, body }) => {
    const csrf = document.cookie.match(/(?:^|; )nobarsync_csrf=([^;]+)/)?.[1] || ""
    const response = await fetch(`/api/v1${path}`, { method: "POST", headers: { "content-type": "application/json", "x-nobarsync-csrf": decodeURIComponent(csrf) }, body: JSON.stringify(body) })
    if (!response.ok) throw new Error(await response.text())
    return response.json()
  }, { path, body })
}

test("mobile direct watch gets film, live audience, chat and voice", async ({ browser }) => {
  test.setTimeout(120000)
  const contexts = await Promise.all([browser.newContext({ permissions: ["microphone"] }), browser.newContext({ permissions: ["microphone"], viewport: { width: 393, height: 851 }, isMobile: true, hasTouch: true })])
  const pages = await Promise.all(contexts.map(c => c.newPage()))
  const [host, guest] = pages
  let code = ""
  try {
    for (const [i, page] of pages.entries()) {
      await page.addInitScript(() => {
        const contexts: AudioContext[] = []
        const streams: MediaStream[] = []
        const gains: GainNode[] = []
        const metrics = { nonzeroOutput: 0 }
        Object.assign(window, { __contexts: contexts, __streams: streams, __gains: gains, __audioMetrics: metrics })
        // The test must still work when direct WebRTC is unavailable.
        window.RTCPeerConnection = class { constructor() { throw new Error("No direct WebRTC in this test") } } as unknown as typeof RTCPeerConnection
        const Original = window.AudioContext
        window.AudioContext = class extends Original { constructor(options?: AudioContextOptions) { super(options); contexts.push(this) } }
        const createGain = BaseAudioContext.prototype.createGain
        BaseAudioContext.prototype.createGain = function () { const node = createGain.call(this); gains.push(node); return node }
        const start = AudioBufferSourceNode.prototype.start
        AudioBufferSourceNode.prototype.start = function (...args) {
          if (this.buffer) for (const value of this.buffer.getChannelData(0)) if (Math.abs(value) > 0.001) metrics.nonzeroOutput++
          return start.apply(this, args)
        }
        const getUserMedia = navigator.mediaDevices.getUserMedia.bind(navigator.mediaDevices)
        navigator.mediaDevices.getUserMedia = async constraints => {
          if ((window as unknown as { __denyMic?: boolean }).__denyMic) throw new DOMException("Denied", "NotAllowedError")
          const stream = await getUserMedia(constraints); streams.push(stream); return stream
        }
      })
      await page.goto("/")
      await post(page, "/auth/register", { display_name: `Call E2E ${i}`, email: `call-${Date.now()}-${i}@example.com`, password: "password123" })
    }
    const film = (await post(host, "/media/youtube", { title: "Film E2E bersama", url: "https://www.youtube.com/watch?v=aqz-KE-bpKQ" })).media
    code = (await post(host, "/rooms", { title: "Judul ruang berbeda", visibility: "public", media_id: film.id })).room.code
    for (const page of pages) {
      await page.goto(`/watch/${code}`)
      await expect(page.getByRole("heading", { name: "Film E2E bersama", exact: true })).toBeVisible({ timeout: 30000 })
      await expect(page.getByText("● LIVE ROOM", {exact: true})).toBeVisible()
      await page.getByRole("button", { name: "Gabung call", exact: true }).click()
      await expect(page.getByRole("button", { name: "Tahan untuk bicara" })).toBeVisible({ timeout: 20000 }).catch(async error => { console.log(await page.locator(".voice-panel").innerText()); throw error })
      await expect.poll(() => page.evaluate(() => {
        const streams = (window as unknown as { __streams: MediaStream[] }).__streams
        return streams[streams.length - 1]?.getAudioTracks()[0]?.enabled ?? true
      })).toBe(false)
    }
    await expect(host.locator(".audience-card")).toHaveCount(2)
    await expect(host.locator(".audience-card").filter({hasText:"Call E2E 1"})).toHaveCount(1)
    await guest.getByLabel("Pesan chat", {exact:true}).fill("Halo dari mobile")
    await guest.getByRole("button", {name:"Kirim pesan",exact:true}).click()
    await expect(host.getByRole("log").getByText("Halo dari mobile",{exact:true})).toBeVisible()
    for (const page of pages) {
      await expect(page.locator('.voice-person[data-state="connected"]')).toHaveCount(2, { timeout: 30000 })
      await expect(page.locator(".voice-person").filter({ hasNotText: "(Anda)" })).toContainText("🔇")
    }
    for (const page of pages) await holdTalk(page, true)
    for (const page of pages) {
      await expect.poll(() => page.evaluate(() => (window as unknown as { __audioMetrics: {nonzeroOutput: number} }).__audioMetrics.nonzeroOutput)).toBeGreaterThan(1000)
      await expect.poll(async () => Number(await page.locator(".voice-person").filter({hasNotText:"(Anda)"}).getAttribute("data-received-frames"))).toBeGreaterThan(1)
    }
    await expect.poll(() => host.locator("video").evaluate((v: HTMLVideoElement) => v.volume)).toBe(0)
    expect(Number(await host.getByLabel("Volume", { exact: true }).inputValue())).toBe(1)
    await host.getByLabel("Volume call", { exact: true }).fill("25")
    expect(await host.evaluate(() => (window as unknown as { __gains: GainNode[] }).__gains.some(g => g.gain.value === 0.25))).toBe(true)
    expect(await host.locator("video").evaluate((v: HTMLVideoElement) => v.volume)).toBe(0)
    for (const page of pages) await holdTalk(page, false)
    expect(await host.evaluate(() => (window as unknown as { __streams: MediaStream[] }).__streams[0].getAudioTracks()[0].enabled)).toBe(false)
    await expect.poll(() => host.locator("video").evaluate((v: HTMLVideoElement) => v.volume)).toBe(1)
    await expect(guest.locator(".voice-person").filter({ hasText: "Call E2E 0" })).toContainText("🔇")
    await host.getByRole("button", { name: "Keluar call" }).click()
    await expect(guest.locator(".voice-person")).toHaveCount(1)
    expect(await host.evaluate(() => (window as unknown as { __contexts: AudioContext[] }).__contexts.every(c => c.state === "closed"))).toBe(true)
    expect(await host.evaluate(() => (window as unknown as { __streams: MediaStream[] }).__streams.every(s => s.getTracks().every(t => t.readyState === "ended")))).toBe(true)
    await host.getByRole("button", { name: "Gabung call", exact: true }).click()
    await expect(guest.locator('.voice-person[data-state="connected"]')).toHaveCount(2, { timeout: 30000 })
    await guest.goto("/dashboard")
    await expect(host.locator(".audience-card")).toHaveCount(1)
    await post(host, `/rooms/${code}/close`, {})
    await expect.poll(() => guest.evaluate(() => (window as unknown as { __contexts: AudioContext[] }).__contexts.every(c => c.state === "closed")), { timeout: 10000 }).toBe(true)
  } finally {
    if (code) await post(host, `/rooms/${code}/close`, {}).catch(() => {})
    await Promise.all(contexts.map(c => c.close()))
  }
})



