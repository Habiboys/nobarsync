import { useEffect, useRef, useState, type ReactNode } from "react"
import { Socket, type Channel } from "phoenix"
import { useLocation } from "react-router"
import { useQueryClient } from "@tanstack/react-query"
import { api, ApiError } from "./api"
import { useSession } from "./session"

import { ActivityContext } from "./activity"

export function ActivityProvider({ children }: { children: ReactNode }) {
  const session = useSession()
  const id = session.data?.user?.id
  const path = useLocation().pathname
  const currentPath = useRef(path)
  const channel = useRef<Channel | null>(null)
  const [socket, setSocket] = useState<Socket | null>(null)
  const client = useQueryClient()
  useEffect(() => { currentPath.current = path; channel.current?.push("activity.page", { page: path }) }, [path])
  useEffect(() => {
    if (!id) return
    let stopped = false
    let connection: Socket | undefined
    let token = ""
    const refresh = async () => {
      try { token = (await api<{ token: string }>("/api/v1/auth/socket-token", { method: "POST" })).token }
      catch (cause) {
        if (cause instanceof ApiError && [401, 403].includes(cause.status)) {
          connection?.disconnect(); void client.invalidateQueries({ queryKey: ["me"] })
        }
        throw cause
      }
    }
    void refresh().then(() => {
      if (stopped) return
      connection = new Socket("/socket", { params: () => ({ token }), timeout: 30000 })
      connection.connect()
      const own = connection.channel(`user:${id}`, {})
      channel.current = own
      own.join().receive("ok", () => own.push("activity.page", { page: currentPath.current }))
      setSocket(connection)
    }).catch(() => {})
    const timer = window.setInterval(() => { void refresh().catch(() => {}) }, 60000)
    return () => { stopped = true; window.clearInterval(timer); channel.current = null; connection?.disconnect() }
  }, [id, client])
  return <ActivityContext.Provider value={id ? socket : null}>{children}</ActivityContext.Provider>
}

