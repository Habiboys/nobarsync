import { test, expect, type Page } from "@playwright/test"

async function api(page:Page, method:string, path:string, body?:object) {
  return page.evaluate(async ({method,path,body}) => {
    const csrf=decodeURIComponent(document.cookie.match(/(?:^|; )nobarsync_csrf=([^;]+)/)?.[1] || "")
    const response=await fetch(`/api/v1${path}`,{method,headers:{"content-type":"application/json","x-nobarsync-csrf":csrf},...(body?{body:JSON.stringify(body)}:{})})
    return {status:response.status,data:await response.json()}
  },{method,path,body})
}

test("live admin, room observer and multiple tabs track actual connections", async ({browser})=>{
  test.skip(!process.env.E2E_ADMIN_EMAIL || !process.env.E2E_ADMIN_PASSWORD, "Set admin test credentials for the monitoring integration check")
  test.setTimeout(150000)
  const adminContext=await browser.newContext(), hostContext=await browser.newContext(), viewerContext=await browser.newContext()
  const admin=await adminContext.newPage(), host=await hostContext.newPage(), viewer=await viewerContext.newPage(), detail=await hostContext.newPage()
  const errors:string[]=[]
  for(const page of [admin,host,viewer,detail]) page.on("pageerror",e=>errors.push(e.message))
  const suffix=Date.now()
  const hostName=`Host langsung ${suffix}`, viewerName=`Viewer langsung ${suffix}`
  let code="",mediaId=""
  try {
    await admin.goto("/")
    expect((await api(admin,"POST","/auth/login",{email:process.env.E2E_ADMIN_EMAIL,password:process.env.E2E_ADMIN_PASSWORD})).status).toBe(200)
    for(const [page,name] of [[host,hostName],[viewer,viewerName]] as [Page,string][]) {
      await page.goto("/")
      expect((await api(page,"POST","/auth/register",{email:`${name.replaceAll(" ","-")}@example.com`,display_name:name,password:"password123"})).status).toBe(200)
    }
    const asset=await api(host,"POST","/media/youtube",{url:"https://youtu.be/aqz-KE-bpKQ",title:`Film langsung ${suffix}`})
    mediaId=asset.data.media.id
    const room=await api(host,"POST","/rooms",{title:`Ruang langsung ${suffix}`,visibility:"public",media_id:mediaId})
    code=room.data.room.code
    expect((await api(viewer,"POST",`/rooms/${code}/join`,{})).status).toBe(200)
    expect((await api(viewer,"GET","/admin/live")).status).toBe(403)
    await host.goto(`/watch/${code}`)
    await expect(host.locator(".watch-header").getByText("Terhubung",{exact:true})).toBeVisible({timeout:20000}).catch(error=>{throw new Error(`${error.message}; page errors: ${JSON.stringify(errors)}; state: ${host.url()}`)})
    await viewer.goto("/library")
    await detail.goto(`/rooms/${code}`)
    await expect(detail.getByText(`${hostName} · Host`,{exact:true})).toBeVisible()
    await expect(detail.getByText(`${viewerName} · Penonton`,{exact:true})).toHaveCount(0)
    await admin.goto("/admin")
    await admin.getByRole("tab",{name:"Langsung",exact:true}).click()
    const online=admin.locator("section.panel").filter({has:admin.getByRole("heading",{name:"Akun online",exact:true})})
    await expect(online.getByText(viewerName,{exact:true})).toBeVisible()
    await expect(online.getByText(hostName,{exact:true})).toBeVisible()
    await viewer.goto(`/watch/${code}`)
    await expect(viewer.locator(".watch-header").getByText("Terhubung",{exact:true})).toBeVisible({timeout:20000})
    await expect(detail.getByText(`${viewerName} · Penonton`,{exact:true})).toBeVisible()
    const second=await viewerContext.newPage()
    await second.goto(`/watch/${code}`)
    await expect(second.locator(".watch-header").getByText("Terhubung",{exact:true})).toBeVisible({timeout:20000})
    await expect(detail.getByText(`${viewerName} · Penonton`,{exact:true})).toHaveCount(1)
    await viewer.goto("/library")
    await expect(detail.getByText(`${viewerName} · Penonton`,{exact:true})).toBeVisible()
    await second.close()
    await expect(detail.getByText(`${viewerName} · Penonton`,{exact:true})).toHaveCount(0)
    await expect(online.getByText(viewerName,{exact:true})).toBeVisible()
    await admin.getByLabel("Cari ruang, film, atau peserta",{exact:true}).fill(code)
    const liveRoom=admin.locator(".live-rooms .panel")
    await expect(liveRoom).toHaveCount(1)
    await expect(liveRoom).toContainText(`Film langsung ${suffix}`)
    await expect(liveRoom).toContainText("1 orang")
    await admin.getByLabel("Hanya ruang berpenghuni",{exact:true}).check()
    for(const mode of ["light","dark"]) {
      await admin.evaluate(value=>localStorage.setItem("manonton-theme",value),mode)
      await admin.reload(); await admin.getByRole("tab",{name:"Langsung",exact:true}).click()
      for(const width of [393,768,1440]) {
        await admin.setViewportSize({width,height:900})
        expect(await admin.evaluate(()=>document.documentElement.scrollWidth <= innerWidth+1)).toBe(true)
        await admin.screenshot({path:`C:/Users/HP/Documents/Codex/2026-11-08/halo/work/live-${mode}-${width}.png`,fullPage:true})
      }
    }
    await admin.getByRole("button",{name:"Perbarui",exact:true}).click()
    await admin.getByLabel("Cari ruang, film, atau peserta",{exact:true}).fill(code)
    await admin.locator(".live-rooms").getByRole("link",{name:"Lihat detail ruang",exact:true}).click()
    await expect(admin).toHaveURL(`/rooms/${code}`)
    await admin.goBack()
    await admin.getByRole("tab",{name:"Langsung",exact:true}).click()
    await viewerContext.close()
    await expect(online.getByText(viewerName,{exact:true})).toHaveCount(0)
    expect((await api(host,"POST",`/rooms/${code}/leave`,{})).status).toBe(200)
    await expect(host).toHaveURL("/dashboard")
    await expect(detail.getByText(`${hostName} · Host`,{exact:true})).toHaveCount(0)
    await expect(detail.getByText("Belum ada yang masuk pemutar.",{exact:true})).toBeVisible()
    expect(errors).toEqual([])
  } finally {
    if(code) {await api(admin,"POST",`/rooms/${code}/close`,{}).catch(()=>{}); await api(admin,"DELETE",`/rooms/${code}`).catch(()=>{})}
    if(mediaId) await api(admin,"DELETE",`/media/${mediaId}`).catch(()=>{})
    await Promise.all([adminContext.close(),hostContext.close(),viewerContext.close()])
  }
})

test("URL import explains HTML players and pasted quotes inline",async({page})=>{
  test.skip(process.env.E2E_CHECK_REMOTE_IMPORT !== "1", "Requires network access and acefile.co in the source allowlist")
  await page.goto("/")
  expect((await api(page,"POST","/auth/register",{email:`url-check-${Date.now()}@example.com`,display_name:"Uji impor",password:"password123"})).status).toBe(200)
  await page.goto("/library?upload=1")
  const modal=page.getByRole("dialog",{name:"Tambah film",exact:true})
  await modal.getByRole("radio",{name:"URL langsung",exact:true}).check()
  await modal.getByLabel("URL video langsung",{exact:true}).fill('https://acefile.co/player/112444782"')
  await modal.getByRole("button",{name:"Impor video",exact:true}).click()
  await expect(modal.getByRole("alert")).toContainText("tanpa tanda kutip")
  await modal.getByLabel("URL video langsung",{exact:true}).fill("https://acefile.co/player/112444782")
  await modal.getByRole("button",{name:"Impor video",exact:true}).click()
  await expect(modal.getByRole("alert")).toContainText("halaman player",{timeout:30000})
  await modal.screenshot({path:"C:/Users/HP/Documents/Codex/2026-11-08/halo/work/url-import-error.png"})
  await page.keyboard.press("Escape")
  await expect(modal).not.toBeVisible()
})
