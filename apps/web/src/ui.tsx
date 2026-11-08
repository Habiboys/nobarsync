import type { ButtonHTMLAttributes, InputHTMLAttributes, ReactNode } from "react"
import { useToasts } from "./toasts"
import { useEffect } from "react"

export function Toasts() {
  const items = useToasts((state) => state.items)
  useEffect(() => {
    if (!items.length) return
    const timer = window.setTimeout(() => useToasts.setState((state) => ({ items: state.items.slice(1) })), 5000)
    return () => window.clearTimeout(timer)
  }, [items])
  return (
    <div className="fixed right-4 bottom-4 z-50 flex w-80 max-w-[calc(100vw-2rem)] flex-col gap-2" role="status" aria-live="polite">
      {items.map((item) => (
        <div
          key={item.id}
          className="rounded-xl border border-white/15 bg-zinc-900/95 px-4 py-3 text-sm text-zinc-100 shadow-2xl backdrop-blur"
        >
          {item.text}
        </div>
      ))}
    </div>
  )
}

export function Button(
  props: ButtonHTMLAttributes<HTMLButtonElement> & { tone?: "amber" | "ghost" | "danger" }
) {
  const { tone = "amber", className = "", ...rest } = props
  const look =
    tone === "amber"
      ? "bg-amber text-white shadow-sm shadow-amber/25 hover:brightness-110"
      : tone === "danger"
        ? "border border-red-500/40 bg-red-500/15 text-red-200 hover:bg-red-500/25"
        : "border border-white/12 bg-white/5 text-zinc-100 hover:bg-white/10"
  return (
    <button
      className={`inline-flex items-center justify-center gap-1.5 rounded-xl px-4 py-2 text-sm font-semibold transition ${look} ${className}`}
      {...rest}
    />
  )
}

export function Field(props: InputHTMLAttributes<HTMLInputElement> & { label: string }) {
  const { label, className = "", ...rest } = props
  return (
    <label className="block text-sm">
      <span className="mb-1.5 block font-medium text-zinc-300">{label}</span>
      <input
        className={`w-full rounded-xl border border-white/12 bg-[#181824] px-3.5 py-2.5 text-zinc-100 placeholder:text-zinc-500 focus:border-amber ${className}`}
        {...rest}
      />
    </label>
  )
}

export function Panel(props: { title?: string; subtitle?: string; right?: ReactNode; children: ReactNode; className?: string }) {
  return (
    <section className={`rounded-2xl border border-white/10 bg-panel/95 p-5 shadow-xl ${props.className || ""}`}>
      {props.title || props.right ? (
        <div className="mb-4 flex flex-wrap items-center justify-between gap-2">
          <div>
            {props.title ? <h2 className="font-display text-xl font-bold tracking-tight text-white">{props.title}</h2> : null}
            {props.subtitle ? <p className="mt-0.5 text-xs text-mist">{props.subtitle}</p> : null}
          </div>
          {props.right}
        </div>
      ) : null}
      {props.children}
    </section>
  )
}

export function Badge(props: { tone?: "green" | "amber" | "red" | "slate" | "brand"; children: ReactNode }) {
  const { tone = "slate", children } = props
  const style =
    tone === "green"
      ? "border-emerald-500/30 bg-emerald-500/15 text-emerald-300"
      : tone === "amber"
        ? "border-amber-500/35 bg-amber-500/15 text-amber-300"
        : tone === "red"
          ? "border-red-500/35 bg-red-500/15 text-red-300"
          : tone === "brand"
            ? "border-red-500/40 bg-amber/20 text-red-200"
            : "border-white/12 bg-white/5 text-zinc-300"
  return (
    <span className={`inline-flex items-center gap-1 rounded-full border px-2.5 py-0.5 text-xs font-medium ${style}`}>
      {children}
    </span>
  )
}
