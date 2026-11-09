import { useState, type KeyboardEvent } from "react"
import { useQuery } from "@tanstack/react-query"
import { api } from "./api"
import { AdminUsers } from "./AdminUsers"
import { AdminAudit } from "./AdminAudit"
import { Panel } from "./ui"

const tabs = [{ id: "users", label: "Pengguna" }, { id: "audit", label: "Jejak tindakan" }, { id: "system", label: "Sistem" }] as const
type Tab = typeof tabs[number]["id"]

export function AdminConsole({ me }: { me: string }) {
  const [tab, setTab] = useState<Tab>("users")
  const metrics = useQuery({ queryKey: ["admin", "metrics"], queryFn: () => api<{ counts: Record<string, number> }>("/api/v1/admin/metrics"), enabled: tab === "system" })
  const jobs = useQuery({ queryKey: ["admin", "jobs"], queryFn: () => api<{ jobs: { id: number; state: string; queue: string; attempt: number }[] }>("/api/v1/admin/jobs"), enabled: tab === "system", refetchInterval: tab === "system" ? 10000 : false })
  function navigateTab(event: KeyboardEvent<HTMLDivElement>) {
    if (!["ArrowLeft", "ArrowRight", "Home", "End"].includes(event.key)) return
    event.preventDefault()
    const index = tabs.findIndex(item => item.id === tab)
    const next = event.key === "Home" ? 0 : event.key === "End" ? tabs.length - 1 : (index + (event.key === "ArrowRight" ? 1 : -1) + tabs.length) % tabs.length
    setTab(tabs[next].id)
    document.getElementById(`admin-tab-${tabs[next].id}`)?.focus()
  }
  return <>
    <div className="page-heading"><div><h1>Administrasi</h1><p>Akun pengguna dan operasional Manonton.</p></div></div>
    <div className="admin-tabs" role="tablist" aria-label="Administrasi" onKeyDown={navigateTab}>{tabs.map(item => <button key={item.id} id={`admin-tab-${item.id}`} role="tab" aria-selected={tab === item.id} aria-controls={`admin-panel-${item.id}`} tabIndex={tab === item.id ? 0 : -1} onClick={() => setTab(item.id)}>{item.label}</button>)}</div>
    <section id={`admin-panel-${tab}`} role="tabpanel" aria-labelledby={`admin-tab-${tab}`}>
      {tab === "users" ? <AdminUsers me={me} /> : tab === "audit" ? <AdminAudit /> : <>
        {metrics.error ? <p role="alert">Ringkasan sistem gagal dimuat: {metrics.error.message}</p> : null}
        {metrics.isPending ? <p role="status">Memuat ringkasan sistem…</p> : null}
        <dl className="system-counts">{Object.entries(metrics.data?.counts || {}).map(([key, value]) => <div key={key}><dt>{({ users: "Pengguna", media: "Film", ready_media: "Film siap", open_rooms: "Ruang aktif" } as Record<string, string>)[key] || key}</dt><dd>{value}</dd></div>)}</dl>
        <Panel title="Pengolahan media" subtitle="Antrean diperbarui setiap 10 detik selama tab ini terbuka.">
          {jobs.isPending ? <p role="status">Memuat antrean pengolahan…</p> : null}
          {jobs.error ? <p role="alert">Antrean gagal dimuat: {jobs.error.message}</p> : null}
          <div className="table-scroll"><table className="data-table"><thead><tr><th>Job</th><th>Antrean</th><th>Status</th><th>Percobaan</th></tr></thead><tbody>{jobs.data?.jobs.map(job => <tr key={job.id}><td>#{job.id}</td><td>{job.queue}</td><td>{job.state}</td><td>{job.attempt}</td></tr>)}</tbody></table></div>
          {jobs.data?.jobs.length === 0 ? <p className="empty-message">Belum ada pekerjaan pengolahan media.</p> : null}
        </Panel>
      </>}
    </section>
  </>
}
