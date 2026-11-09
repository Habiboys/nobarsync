import { useEffect, useState, type ReactNode } from "react"
import { ThemeContext, type Theme } from "./theme"

export function ThemeProvider({ children }: { children: ReactNode }) {
  const [theme, setTheme] = useState<Theme>(() => document.documentElement.dataset.theme === "light" ? "light" : "dark")
  useEffect(() => {
    document.documentElement.dataset.theme = theme
    document.querySelector('meta[name="theme-color"]')?.setAttribute("content", theme === "light" ? "#f3f0e8" : "#111512")
  }, [theme])
  useEffect(() => {
    const preference = window.matchMedia("(prefers-color-scheme: dark)")
    const followSystem = () => {
      try { if (localStorage.getItem("manonton-theme")) return } catch { /* Storage can be disabled in private contexts. */ }
      setTheme(preference.matches ? "dark" : "light")
    }
    preference.addEventListener("change", followSystem)
    return () => preference.removeEventListener("change", followSystem)
  }, [])
  function toggle() {
    const next = theme === "dark" ? "light" : "dark"
    try { localStorage.setItem("manonton-theme", next) } catch { /* The toggle still works without persistence. */ }
    setTheme(next)
  }
  return <ThemeContext.Provider value={{ theme, toggle }}>{children}</ThemeContext.Provider>
}
