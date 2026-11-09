import { chromium } from "playwright"
import { execSync } from "node:child_process"

const base = "http://127.0.0.1:5178"
const email = `probe-admin-${Date.now()}@example.com`
const out = process.argv[2]
const browser = await chromium.launch()
const context = await browser.newContext()
const page = await context.newPage()
await page.goto(base + "/")
const call = (method, path, body) => page.evaluate(async ([method, path, body]) => {
  const csrf = decodeURIComponent(document.cookie.match(/(?:^|; )nobarsync_csrf=([^;]+)/)?.[1] || "")
  const r = await fetch("/api/v1" + path, { method, headers: { "content-type": "application/json", "x-nobarsync-csrf": csrf }, body: body ? JSON.stringify(body) : undefined })
  return { status: r.status, data: await r.json().catch(() => null) }
}, [method, path, body])
const reg = await call("POST", "/auth/register", { email, password: "password123", display_name: "Admin uji film" })
console.log("register", reg.status)
execSync(`docker exec nobarkan2-postgres-1 psql -U postgres -d nobarsync -c "update users set role='admin' where email='${email}'"`, { stdio: "inherit" })
const yt = await call("POST", "/media/youtube", { title: "Film uji admin", url: "https://www.youtube.com/watch?v=aqz-KE-bpKQ" })
console.log("youtube", yt.status)
const list = await call("GET", "/admin/media?search=" + encodeURIComponent(email))
console.log("admin list", list.status, list.data?.total, list.data?.items?.[0]?.owner?.email === email)
for (const mode of ["light", "dark"]) for (const width of [390, 820, 1360]) {
  await page.setViewportSize({ width, height: 900 })
  await page.goto(base + "/admin")
  if (await page.locator("html").getAttribute("data-theme") !== mode) await page.getByRole("button", { name: mode === "light" ? "Gunakan mode terang" : "Gunakan mode gelap", exact: true }).click()
  await page.getByRole("tab", { name: "Film" }).click()
  await page.getByPlaceholder("Judul, nama, atau email pemilik").fill(email)
  await page.getByRole("button", { name: "Kelola Film uji admin" }).waitFor()
  await page.screenshot({ path: `${out}/admin-media-${mode}-${width}.png`, fullPage: true })
  if (width === 1360 || width === 390) {
    await page.getByRole("button", { name: "Kelola Film uji admin" }).click()
    await page.getByRole("button", { name: "Hapus film" }).click()
    await page.screenshot({ path: `${out}/admin-media-drawer-${mode}-${width}.png` })
    await page.keyboard.press("Escape")
  }
}
await page.getByRole("button", { name: "Kelola Film uji admin" }).click()
await page.getByLabel("Judul film").fill("Film uji admin diubah")
await page.getByLabel("Alasan tindakan").fill("Uji ubah film")
await page.getByRole("button", { name: "Simpan film" }).click()
await page.getByRole("button", { name: "Kelola Film uji admin diubah" }).click()
await page.getByLabel("Alasan tindakan").fill("Uji hapus film")
await page.getByRole("button", { name: "Hapus film" }).click()
await page.getByRole("button", { name: "Hapus permanen" }).click()
await page.getByText("Tidak ada film yang sesuai").waitFor()
await page.getByRole("tab", { name: "Jejak tindakan" }).click()
await page.getByText("Uji hapus film").waitFor()
await page.screenshot({ path: `${out}/admin-media-audit.png` })
console.log("edit+delete+audit ok")
execSync(`docker exec nobarkan2-postgres-1 psql -U postgres -d nobarsync -c "update users set role='user', status='suspended' where email='${email}'"`, { stdio: "inherit" })
await browser.close()
