import { useQuery } from "@tanstack/react-query"
import { api } from "./api"
import type { Guest, User } from "./api"

export function useSession() {
  return useQuery({
    queryKey: ["me"],
    queryFn: () => api<{ user: User | null; guest: Guest | null }>("/api/v1/auth/me"),
  })
}
