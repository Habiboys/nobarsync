import { useQuery } from "@tanstack/react-query"
import { api } from "./api"
import { Button, Panel } from "./ui"

type AuditEvent = { id: string; action: string; actor: string | null; resource_id: string; metadata: { reason?: string; before?: Record<string, string>; after?: Record<string, string> }; inserted_at: string }

export function AdminAudit() {
  const audit = useQuery({ queryKey: ["admin", "audit"], queryFn: () => api<{ events: AuditEvent[] }>("/api/v1/admin/audit") })
  return <Panel title="Jejak tindakan admin" subtitle="50 perubahan akun dan pencabutan sesi terbaru." right={<Button tone="ghost" disabled={audit.isFetching} onClick={() => void audit.refetch()}>Muat ulang</Button>}>
    {audit.isPending ? <p role="status">Memuat jejak tindakan…</p> : null}
    {audit.error ? <p role="alert">Jejak tindakan gagal dimuat: {audit.error.message}</p> : null}
    <ol className="audit-list">{audit.data?.events.map(event => <li key={event.id}>
      <div className="audit-heading"><strong>{event.actor || "Admin"}: {event.action === "admin.sessions_revoke" ? "cabut sesi" : "ubah akun"}</strong><time>{new Date(event.inserted_at).toLocaleString("id-ID", { timeZone: "Asia/Jakarta" })} WIB</time></div>
      <p>{event.metadata.reason}</p><dl className="audit-details"><div><dt>Akun</dt><dd>{event.metadata.after?.display_name || event.resource_id}</dd></div><div><dt>Peran</dt><dd>{event.metadata.before?.role} ke {event.metadata.after?.role}</dd></div><div><dt>Status</dt><dd>{event.metadata.before?.status} ke {event.metadata.after?.status}</dd></div></dl>
    </li>)}</ol>
    {audit.data?.events.length === 0 ? <p className="empty-message">Belum ada perubahan akun oleh admin.</p> : null}
  </Panel>
}
