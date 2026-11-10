import { createContext, useContext, useEffect } from "react"
import { Socket } from "phoenix"
import { useQueryClient } from "@tanstack/react-query"

export const ActivityContext = createContext<Socket | null>(null)

export function useActivityUpdates(topic: string | null, queryKey: string[]) {
  const socket = useContext(ActivityContext)
  const client = useQueryClient()
  const key = JSON.stringify(queryKey)
  useEffect(() => {
    if (!socket || !topic) return
    const observer = socket.channel(topic, {})
    const refresh = () => { void client.invalidateQueries({ queryKey: JSON.parse(key) as string[] }) }
    observer.on("activity.changed", refresh)
    observer.join().receive("ok", refresh)
    return () => { observer.leave() }
  }, [socket, topic, key, client])
}
