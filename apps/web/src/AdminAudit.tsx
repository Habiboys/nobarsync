import { useQuery } from "@tanstack/react-query"
import { api } from "./api"
import { Button, Panel } from "./ui"

type AuditEvent = { id: string; action: string; actor: string | null; resource_id: string; metadata: { reason?: string; before?: Record<string, string>; after?: Record<string, string>; owner?: { display_name?: string; email?: string } | null }; inserted_at: string }

const actionLabel: Record<string, string> = { "admin.sessions_revoke": "cabut sesi", "admin.media_update": "ubah film", "admin.media_delete": "hapus film" }
const visibilityLabel = (value?: string) => value === "library" ? "Pustaka bersama" : value === "private" ? "Pribadi" : value
const shareLabel = (value?: string) => ({ none: "Tidak diajukan", pending: "Menunggu", approved: "Disetujui", rejected: "Ditolak" } as Record<string, string>)[value || ""] || value

function Details({ event }: { event: AuditEvent }) {
  const { before, after, owner } = event.metadata
  if (event.action.startsWith("admin.media_")) return <dl className="audit-details">
    <div><dt>Film</dt><dd>{before?.title || event.resource_id}{after && after.title !== before?.title ? ` ke ${after.title}` : ""}</dd></div>
    <div><dt>Pemilik</dt><dd>{owner?.email || owner?.display_name || "Tidak diketahui"}</dd></div>
    {after ? <div><dt>Akses</dt><dd>{visibilityLabel(before?.visibility)} ke {visibilityLabel(after.visibility)}</dd></div> : null}
    {after?.share_request ? <div><dt>Persetujuan</dt><dd>{shareLabel(before?.share_request)} ke {shareLabel(after.share_request)}</dd></div> : null}
  </dl>
  return <dl className="audit-details"><div><dt>Akun</dt><dd>{after?.display_name || event.resource_id}</dd></div><div><dt>Peran</dt><dd>{before?.role} ke {after?.role}</dd></div><div><dt>Status</dt><dd>{before?.status} ke {after?.status}</dd></div></dl>
}

export function AdminAudit() {
  const audit = useQuery({ queryKey: ["admin", "audit"], queryFn: () => api<{ events: AuditEvent[] }>("/api/v1/admin/audit") })
  return <Panel title="Jejak tindakan admin" subtitle="50 tindakan admin terbaru pada akun dan film." right={<Button tone="ghost" disabled={audit.isFetching} onClick={() => void audit.refetch()}>Muat ulang</Button>}>
    {audit.isPending ? <p role="status">Memuat jejak tindakan…</p> : null}
    {audit.error ? <p role="alert">Jejak tindakan gagal dimuat: {audit.error.message}</p> : null}
    <ol className="audit-list">{audit.data?.events.map(event => <li key={event.id}>
      <div className="audit-heading"><strong>{event.actor || "Admin"}: {actionLabel[event.action] || "ubah akun"}</strong><time>{new Date(event.inserted_at).toLocaleString("id-ID", { timeZone: "Asia/Jakarta" })} WIB</time></div>
      <p>{event.metadata.reason}</p><Details event={event} />
    </li>)}</ol>
    {audit.data?.events.length === 0 ? <p className="empty-message">Belum ada tindakan admin.</p> : null}
  </Panel>
}
