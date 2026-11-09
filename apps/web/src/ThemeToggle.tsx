import { useTheme } from "./theme"

export function ThemeToggle() {
  const { theme, toggle } = useTheme()
  return <button type="button" className="theme-toggle" onClick={toggle} aria-label={theme === "dark" ? "Gunakan mode terang" : "Gunakan mode gelap"}>{theme === "dark" ? "Mode terang" : "Mode gelap"}</button>
}
