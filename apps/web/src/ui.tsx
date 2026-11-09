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
          className="toast"
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
  const look = tone === "amber" ? "button-primary" : tone === "danger" ? "button-danger" : "button-ghost"
  return (
    <button
      className={`button ${look} ${className}`}
      {...rest}
    />
  )
}

export function Field(props: InputHTMLAttributes<HTMLInputElement> & { label: string }) {
  const { label, className = "", ...rest } = props
  return (
    <label className="field">
      <span>{label}</span>
      <input
        className={`w-full ${className}`}
        {...rest}
      />
    </label>
  )
}

export function Panel(props: { title?: string; subtitle?: string; right?: ReactNode; children: ReactNode; className?: string }) {
  return (
    <section className={`panel ${props.className || ""}`}>
      {props.title || props.right ? (
        <div className="panel-heading">
          <div>
            {props.title ? <h2>{props.title}</h2> : null}
            {props.subtitle ? <p>{props.subtitle}</p> : null}
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
  return (
    <span className={`status-label status-${tone}`}>
      {children}
    </span>
  )
}
