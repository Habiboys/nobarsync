import { QueryClient, QueryClientProvider } from "@tanstack/react-query"
import { Component, StrictMode } from "react"
import type { ReactNode } from "react"
import { createRoot } from "react-dom/client"
import { BrowserRouter } from "react-router"
import { App } from "./App"
import { Toasts } from "./ui"
import "@fontsource/outfit/latin-400.css"
import "@fontsource/outfit/latin-600.css"
import "./index.css"
import "./cinema.css"

const queryClient = new QueryClient()

class ErrorBoundary extends Component<{ children: ReactNode }, { error: string | null }> {
  state = { error: null as string | null }
  static getDerivedStateFromError(error: Error) {
    return { error: error.message }
  }
  render() {
    if (this.state.error) {
      return <div className="p-8">Terjadi kesalahan: {this.state.error}</div>
    }
    return this.props.children
  }
}

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <ErrorBoundary>
      <QueryClientProvider client={queryClient}>
        <BrowserRouter>
          <App />
          <Toasts />
        </BrowserRouter>
      </QueryClientProvider>
    </ErrorBoundary>
  </StrictMode>,
)
