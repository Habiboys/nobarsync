declare const process: { env: Record<string, string | undefined> }

import tailwindcss from "@tailwindcss/vite"
import react from "@vitejs/plugin-react"
import { defineConfig } from "vitest/config"

const target = process.env.VITE_PROXY_TARGET || "http://localhost:4000"

export default defineConfig({
  plugins: [react(), tailwindcss()],
  server: {
    host: "0.0.0.0",
    port: 5173,
    watch: { usePolling: true, interval: 400 },
    proxy: {
      "/api": target,
      "/socket": { target, ws: true },
      "/media": target,
      "/health": target,
    },
  },
  test: {
    environment: "node",
    include: ["src/**/*.test.ts"],
  },
})
