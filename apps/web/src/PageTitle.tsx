import { useEffect } from "react"
import { useLocation } from "react-router"

const titles: Record<string, string> = { "/": "Nonton bersama", "/login": "Masuk", "/register": "Buat akun", "/dashboard": "Ruang saya", "/library": "Pustaka", "/upload": "Tambah film", "/rooms/new": "Buat ruang", "/join": "Gabung ruang", "/profile": "Akun", "/admin": "Administrasi" }

export function PageTitle() {
  const { pathname } = useLocation()
  useEffect(() => {
    const title = titles[pathname] || (pathname.startsWith("/watch/") ? `Menonton ${pathname.split("/").pop()}` : "Ruang nonton")
    document.title = `${title} | Manonton`
  }, [pathname])
  return null
}
