import { create } from "zustand"

type ToastState = { items: { id: number; text: string }[]; push: (text: string) => void }

export const useToasts = create<ToastState>((set) => ({
  items: [],
  push: (text) =>
    set((state) => ({ items: [...state.items, { id: Date.now() + Math.random(), text }].slice(-4) })),
}))

