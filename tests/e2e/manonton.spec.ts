import { test, expect, type Page } from "@playwright/test"
import { mkdir } from "node:fs/promises"

const shots = "C:/Users/HP/Documents/Codex/2026-11-08/halo/outputs"
async function request(page: Page, method: string, path: string, body?: object) {
  return page.evaluate(async ({ method, path, body }) => {
    const csrf = decodeURIComponent(document.cookie.match(/(?:^|; )nobarsync_csrf=([^;]+)/)?.[1] || "")
    const response = await fetch(`/api/v1${path}`, { method, headers: {"content-type":"application/json","x-nobarsync-csrf":csrf}, ...(body ? {body:JSON.stringify(body)} : {}) })
    const data = await response.json()
    return {status:response.status,data}
  }, {method,path,body})
}
async function theme(page: Page, value: string) {
  if (await page.locator("html").getAttribute("data-theme") !== value) await page.getByRole("button",{name:value === "light" ? "Gunakan mode terang" : "Gunakan mode gelap",exact:true}).click()
  await expect(page.locator("html")).toHaveAttribute("data-theme",value)
}
async function noOverflow(page: Page) {
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth+1)).toBe(true)
}

test("Manonton themes, library modals, preview, and mobile navigation", async ({ browser }) => {
  test.setTimeout(120000)
  await mkdir(shots,{recursive:true})
  const context = await browser.newContext()
  const page = await context.newPage()
  const errors: string[] = []
  page.on("pageerror",error => errors.push(error.message))
  let code="", mediaId=""
  try {
    await page.goto("/register")
    await page.getByLabel("Nama",{exact:true}).fill("Uji tema Manonton")
    await page.getByLabel("Email",{exact:true}).fill(`manonton-ui-${Date.now()}@example.com`)
    await page.getByLabel("Kata sandi",{exact:true}).fill("password123")
    await page.getByRole("button",{name:"Buat akun",exact:true}).click()
    await expect(page).toHaveURL("/dashboard")
    await page.goto("/library")
    await page.getByRole("button",{name:"Tambah film",exact:true}).click()
    const upload=page.getByRole("dialog",{name:"Tambah film",exact:true})
    await expect(upload).toBeVisible()
    await upload.getByRole("radio",{name:"URL langsung",exact:true}).check()
    await expect(upload.getByLabel("URL video langsung",{exact:true})).toBeVisible()
    await upload.getByRole("button",{name:"Impor video",exact:true}).click()
    expect(await upload.getByLabel("URL video langsung",{exact:true}).evaluate((input:HTMLInputElement)=>input.validity.valueMissing)).toBe(true)
    await upload.getByRole("radio",{name:"YouTube",exact:true}).check()
    await upload.getByLabel("Judul (opsional)",{exact:true}).fill("Uji film pratinjau")
    await upload.getByLabel("URL YouTube",{exact:true}).fill("https://www.youtube.com/watch?v=aqz-KE-bpKQ")
    await upload.getByRole("button",{name:"Tambahkan YouTube",exact:true}).click()
    await expect(page.getByRole("heading",{name:"Uji film pratinjau",exact:true})).toBeVisible()
    await page.keyboard.press("Escape")
    await expect(upload).not.toBeVisible()
    const list=await request(page,"GET","/media?q=Uji%20film%20pratinjau")
    mediaId=list.data.items[0].id
    code=(await request(page,"POST","/rooms",{title:"Uji ruang Manonton",visibility:"public",media_id:mediaId})).data.room.code
    await page.getByRole("button",{name:"Pratinjau",exact:true}).click()
    const preview=page.getByRole("dialog",{name:"Uji film pratinjau",exact:true})
    await expect(preview).toBeVisible()
    await expect(preview.locator("iframe")).toHaveAttribute("src",/youtube-nocookie\.com\/embed\/aqz-KE-bpKQ/)
    await preview.getByRole("button",{name:"Tutup",exact:true}).click()
    await page.goto("/upload")
    await expect(page).toHaveURL("/library?upload=1")
    await expect(upload).toBeVisible()
    await upload.getByRole("radio",{name:"Berkas video",exact:true}).check()
    await expect(upload.getByRole("button",{name:"Unggah film",exact:true})).toBeDisabled()
    await page.keyboard.press("Escape")
    const routes=["/", "/dashboard","/library","/join","/rooms/new",`/rooms/${code}`,"/profile",`/watch/${code}`]
    for (const mode of ["light","dark"]) {
      await page.goto("/library"); await theme(page,mode)
      for (const width of [393,768,1440]) {
        await page.setViewportSize({width,height:900})
        for (const route of routes) {
          await page.goto(route)
          await expect(page.locator("html")).toHaveAttribute("data-theme",mode)
          await noOverflow(page)
          await expect(page.getByRole("heading",{level:1})).toHaveCount(1)
        }
        await page.goto("/library")
        await page.screenshot({path:`${shots}/manonton-library-${mode}-${width}.png`,fullPage:true})
      }
    }
    await page.setViewportSize({width:393,height:851})
    await page.goto("/library")
    await page.getByText("Menu",{exact:true}).click()
    await page.getByRole("navigation",{name:"Menu ponsel",exact:true}).getByRole("link",{name:"Akun",exact:true}).click()
    await expect(page).toHaveURL("/profile")
    await page.getByLabel("Nama tampilan",{exact:true}).fill("Nama uji diperbarui")
    await page.getByRole("button",{name:"Simpan profil",exact:true}).click()
    await expect(page.getByRole("status")).toContainText("Profil diperbarui")
    expect(errors).toEqual([])
  } finally {
    if(code) {await request(page,"POST",`/rooms/${code}/close`,{}).catch(()=>{}); await request(page,"DELETE",`/rooms/${code}`).catch(()=>{})}
    if(mediaId) await request(page,"DELETE",`/media/${mediaId}`).catch(()=>{})
    await context.close()
  }
})

test("admin drawer and tabs manage account access and audit with both themes", async ({browser})=>{
  test.setTimeout(120000)
  const admin=await browser.newContext(), user=await browser.newContext()
  const a=await admin.newPage(), u=await user.newPage()
  const email=`manonton-account-${Date.now()}@example.com`
  let id=""
  try {
    await a.goto("/")
    const login=await request(a,"POST","/auth/login",{email:process.env.E2E_ADMIN_EMAIL || "admin@nobarsync.local",password:process.env.E2E_ADMIN_PASSWORD || "nobarsync-dev"})
    expect(login.status).toBe(200)
    await u.goto("/")
    const registered=await request(u,"POST","/auth/register",{email,password:"password123",display_name:"Uji akun Manonton",role:"admin"})
    id=registered.data.user.id
    expect(registered.data.user.role).toBe("user")
    expect((await request(u,"GET","/admin/users")).status).toBe(403)
    await a.goto("/admin")
    await expect(a.getByRole("tab",{name:"Pengguna",exact:true})).toHaveAttribute("aria-selected","true")
    await a.getByLabel("Cari pengguna",{exact:true}).fill(email)
    const manage=a.getByRole("button",{name:`Kelola ${email}`,exact:true})
    await manage.click()
    const drawer=a.getByRole("dialog",{name:"Kelola akun",exact:true})
    await expect(drawer).toBeVisible()
    const box=await drawer.boundingBox()
    expect(box!.x+box!.width).toBeCloseTo(a.viewportSize()!.width,0)
    await a.keyboard.press("Escape")
    await expect(drawer).not.toBeVisible()
    await expect(manage).toBeFocused()
    for(const mode of ["light","dark"]) {
      await theme(a,mode); await manage.click()
      await drawer.getByLabel("Nama pengguna",{exact:true}).fill("Uji akun baru")
      await drawer.getByLabel("Alasan tindakan",{exact:true}).fill(`Uji nama ${mode}`)
      await drawer.getByRole("button",{name:"Simpan akun",exact:true}).click()
      await expect(drawer).not.toBeVisible()
      await expect(a.getByText("Uji akun baru",{exact:true})).toBeVisible()
    }
    await manage.click()
    await drawer.getByLabel("Status akun",{exact:true}).selectOption("suspended")
    await drawer.getByLabel("Alasan tindakan",{exact:true}).fill("Uji suspensi akun")
    await drawer.getByRole("button",{name:"Simpan akun",exact:true}).click()
    await expect(drawer).not.toBeVisible()
    expect((await request(u,"GET","/rooms")).status).toBe(401)
    expect((await request(u,"POST","/auth/login",{email,password:"password123"})).status).toBe(403)
    await a.getByRole("tab",{name:"Jejak tindakan",exact:true}).click()
    await expect(a.getByText("Uji suspensi akun",{exact:true})).toBeVisible()
    await expect(a.getByLabel("Cari pengguna",{exact:true})).toHaveCount(0)
    await a.getByRole("tab",{name:"Sistem",exact:true}).click()
    await expect(a.getByRole("heading",{name:"Pengolahan media",exact:true})).toBeVisible()
    await a.getByRole("tab",{name:"Pengguna",exact:true}).click()
    await a.getByLabel("Cari pengguna",{exact:true}).fill(email)
    await manage.click()
    await drawer.getByLabel("Status akun",{exact:true}).selectOption("active")
    await drawer.getByLabel("Alasan tindakan",{exact:true}).fill("Uji aktivasi akun")
    await drawer.getByRole("button",{name:"Simpan akun",exact:true}).click()
    await expect(drawer).not.toBeVisible()
    expect((await request(u,"POST","/auth/login",{email,password:"password123"})).status).toBe(200)
    await manage.click()
    await drawer.getByLabel("Alasan tindakan",{exact:true}).fill("Uji cabut sesi")
    await drawer.getByRole("button",{name:"Cabut semua sesi",exact:true}).click()
    await expect(drawer).not.toBeVisible()
    expect((await request(u,"GET","/rooms")).status).toBe(401)
    for(const mode of ["light","dark"]) {
      await theme(a,mode)
      for(const width of [393,768,1440]) {
        await a.setViewportSize({width,height:900})
        await manage.click(); await noOverflow(a)
        const bounds=await drawer.boundingBox(); expect(bounds!.width).toBeLessThanOrEqual(width)
        await a.screenshot({path:`${shots}/manonton-admin-${mode}-${width}.png`,fullPage:true})
        await drawer.getByRole("button",{name:"Tutup pengaturan akun",exact:true}).click()
      }
    }
    const ownId=login.data.user.id
    expect((await request(a,"PATCH",`/admin/users/${ownId}`,{status:"suspended",reason:"Uji proteksi admin"})).status).toBe(422)
  } finally {
    if(id) await request(a,"PATCH",`/admin/users/${id}`,{status:"suspended",reason:"Akun pengujian selesai"}).catch(()=>{})
    await admin.close(); await user.close()
  }
})
