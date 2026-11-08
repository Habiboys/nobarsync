import { test, expect, type Page } from "@playwright/test"

async function post(page: Page, path: string, body: object) {
  return page.evaluate(async ({path, body}) => {
    const csrf = decodeURIComponent(document.cookie.match(/(?:^|; )nobarsync_csrf=([^;]+)/)?.[1] || "")
    const response = await fetch(`/api/v1${path}`, { method: "POST", headers: { "content-type": "application/json", "x-nobarsync-csrf": csrf }, body: JSON.stringify(body) })
    if (!response.ok) throw new Error(`HTTP ${response.status}`)
    return response.json()
  }, {path, body})
}

test("public room requires an account and preserves invitation through registration and login", async ({ browser }) => {
  test.setTimeout(120000)
  const host = await browser.newContext()
  const visitor = await browser.newContext()
  const h = await host.newPage(), v = await visitor.newPage()
  let code = ""
  try {
    await h.goto("/")
    await post(h, "/auth/register", {email:`login-host-${Date.now()}@example.com`,password:"password123",display_name:"Host login"})
    code = (await post(h, "/rooms", {title:"Login required E2E",visibility:"public"})).room.code
    await v.goto("/")
    for (const path of [`/rooms/${code}`,`/rooms/${code}/playback`,`/rooms/${code}/messages`,`/rooms/${code}/playlist`]) {
      expect((await visitor.request.get(`/api/v1${path}`)).status()).toBe(401)
    }
    for (const path of [`/rooms/${code}/join`,"/auth/socket-token","/playback/token"]) {
      expect((await visitor.request.post(`/api/v1${path}`, {data:{room_code:code}})).status()).toBe(401)
    }
    expect((await visitor.request.post("/api/v1/auth/guest", {data:{display_name:"Tamu"}})).status()).toBe(404)
    for (const path of [`/watch/${code}`,`/rooms/${code}`]) {
      await v.goto(path)
      await expect(v).toHaveURL(/\/login\?next=/)
      await expect(v.getByRole("button",{name:"Gabung call",exact:true})).toHaveCount(0)
    }
    await v.goto(`/j/${code}`)
    await expect(v).toHaveURL(/\/login\?next=/)
    await v.getByRole("link",{name:"Daftar",exact:true}).click()
    const email=`viewer-login-${Date.now()}@example.com`
    await v.getByLabel("Nama",{exact:true}).fill("Viewer akun")
    await v.getByLabel("Email",{exact:true}).fill(email)
    await v.getByLabel("Kata sandi",{exact:true}).fill("password123")
    await v.getByRole("button",{name:"Buat akun",exact:true}).click()
    await expect(v).toHaveURL(`/watch/${code}`,{timeout:20000})
    await expect(v.getByRole("button",{name:"Gabung call",exact:true})).toBeVisible()
    await post(v,"/auth/logout",{})
    await v.goto(`/j/${code}`)
    await expect(v).toHaveURL(/\/login\?next=/)
    await v.getByLabel("Email",{exact:true}).fill(email)
    await v.getByLabel("Kata sandi",{exact:true}).fill("password123")
    await v.getByRole("button",{name:"Masuk",exact:true}).click()
    await expect(v).toHaveURL(`/watch/${code}`,{timeout:20000})
  } finally {
    if(code) await post(h,`/rooms/${code}/close`,{}).catch(()=>{})
    await host.close(); await visitor.close()
  }
})
