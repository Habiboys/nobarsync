import { defineConfig, devices } from "@playwright/test"

export default defineConfig({
  testDir: ".",
  timeout: 60_000,
  use: { baseURL: process.env.E2E_BASE_URL || "http://localhost:5178" },
  projects: [
    { name: "chromium", use: { ...devices["Desktop Chrome"], channel: process.env.E2E_BROWSER_CHANNEL, launchOptions: { args: ["--disable-background-timer-throttling", "--disable-renderer-backgrounding", "--use-fake-device-for-media-stream", "--use-fake-ui-for-media-stream", "--autoplay-policy=no-user-gesture-required"] } } },
  ],
})



