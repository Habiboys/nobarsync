import { useEffect } from "react"
import { useLocation } from "react-router"

const titles: Record<string, string> = { "/": "Nonton bersama", "/login": "Masuk", "/register": "Buat akun", "/dashboard": "Ruang saya", "/library": "Pustaka", "/upload": "Tambah film", "/rooms/new": "Buat ruang", "/join": "Gabung ruang", "/profile": "Akun", "/admin": "Administrasi" }
const homeTitle = "Manonton - Nonton Bareng Online Gratis"
const homeDescription = "Nonton bareng online gratis di Manonton. Buat ruang, undang teman, dan putar film atau YouTube bersama dengan sinkronisasi, chat, dan voice call."
const descriptions: Record<string, string> = {
  "/login": "Masuk ke akun Manonton untuk melanjutkan nonton bareng teman.",
  "/register": "Buat akun Manonton gratis untuk membuat ruang dan nonton bersama teman.",
}

function setMeta(selector: string, content: string) {
  document.querySelector<HTMLMetaElement>(selector)?.setAttribute("content", content)
}

export function PageTitle() {
  const { pathname } = useLocation()
  useEffect(() => {
    const title = titles[pathname] || (pathname.startsWith("/watch/") ? `Menonton ${pathname.split("/").pop()}` : "Ruang nonton")
    const home = pathname === "/"
    const pageTitle = home ? homeTitle : `${title} | Manonton`
    const description = home ? homeDescription : descriptions[pathname] || "Halaman akun dan ruang nonton Manonton. Masuk untuk melanjutkan."
    document.title = pageTitle
    setMeta('meta[name="description"]', description)
    setMeta('meta[name="robots"]', home ? "index, follow, max-image-preview:large" : "noindex, nofollow")
    setMeta('meta[property="og:title"]', home ? homeTitle : "Manonton - Nonton bersama teman")
    setMeta('meta[property="og:description"]', homeDescription)
    setMeta('meta[name="twitter:title"]', home ? homeTitle : "Manonton - Nonton bersama teman")
    setMeta('meta[name="twitter:description"]', homeDescription)
  }, [pathname])
  return null
}
