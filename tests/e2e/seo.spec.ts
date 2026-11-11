import { test, expect } from "@playwright/test"

const canonical = "https://manonton.neotelemetri.id/"
const title = "Manonton - Nonton Bareng Online Gratis"

test("static SEO and crawler files are available before JavaScript renders", async ({ request }) => {
  const home = await request.get("/")
  expect(home.status()).toBe(200)
  expect(home.headers()["x-robots-tag"]).toBeUndefined()
  const html = await home.text()
  expect(html).toContain(`<title>${title}</title>`)
  expect(html).toContain(`<link rel="canonical" href="${canonical}"`)
  expect(html).toContain('name="robots" content="index, follow, max-image-preview:large"')
  expect(html).toContain('property="og:image" content="https://manonton.neotelemetri.id/manonton.png"')
  const schema = JSON.parse(html.match(/<script type="application\/ld\+json" id="website-schema">([\s\S]*?)<\/script>/)![1])
  expect(schema).toMatchObject({"@type":"WebSite", name:"Manonton",url:canonical,inLanguage:"id-ID"})
  const robots = await request.get("/robots.txt")
  expect(robots.status()).toBe(200)
  expect(robots.headers()["content-type"]).toContain("text/plain")
  expect(await robots.text()).toContain(`Sitemap: ${canonical}sitemap.xml`)
  expect(await robots.text()).not.toContain("Disallow: /\n")
  const sitemap = await request.get("/sitemap.xml")
  expect(sitemap.status()).toBe(200)
  expect(sitemap.headers()["content-type"]).toContain("xml")
  expect((await sitemap.text()).match(/<loc>/g)).toHaveLength(1)
  expect(await sitemap.text()).toContain(`<loc>${canonical}</loc>`)
  for (const path of ["/login", "/register", "/admin", "/library", "/watch/ABC123", "/rooms/ABC123", "/j/ABC123"]) {
    const response = await request.get(path)
    expect(response.headers()["x-robots-tag"], path).toBe("noindex, nofollow")
  }
})

test("route navigation preserves homepage metadata and excludes account pages", async ({ page }) => {
  const errors:string[]=[]
  page.on("pageerror", error => errors.push(error.message))
  await page.goto("/")
  await expect(page).toHaveTitle(title)
  await expect(page.locator('meta[name="robots"]')).toHaveAttribute("content", "index, follow, max-image-preview:large")
  await page.getByRole("link", {name:"Gabung dengan kode",exact:true}).click()
  await expect(page.getByRole("heading",{name:"Masuk ke Manonton",exact:true})).toBeVisible()
  await expect(page).toHaveTitle("Masuk | Manonton")
  await expect(page.locator('meta[name="robots"]')).toHaveAttribute("content","noindex, nofollow")
  await page.goBack()
  await expect(page).toHaveTitle(title)
  await expect(page.locator('meta[name="robots"]')).toHaveAttribute("content", "index, follow, max-image-preview:large")
  await page.goto("/register?next=%2Fwatch%2FPRIVATE")
  await expect(page).toHaveTitle("Buat akun | Manonton")
  await expect(page.locator('meta[name="robots"]')).toHaveAttribute("content","noindex, nofollow")
  await expect(page.locator('meta[property="og:url"]')).toHaveAttribute("content",canonical)
  await expect(page.locator('link[rel="canonical"]')).toHaveCount(1)
  await expect(page.locator('link[rel="canonical"]')).toHaveAttribute("href",canonical)
  expect(errors).toEqual([])
})
