import { useSession } from "./session"
import { Navigate, Outlet, Route, Routes, useLocation } from "react-router"
import { Admin, CreateRoom, Dashboard, Join, Landing, Library, Lobby, Login, Profile, QuickJoin, Register, UploadStudio } from "./pages"
import { lazy, Suspense } from "react"
const WatchRoom = lazy(() => import("./watch").then((module) => ({ default: module.WatchRoom })))

function RequireLogin() {
  const session = useSession()
  const location = useLocation()
  if (session.isPending) return <div className="p-10 text-mist">Memeriksa akun…</div>
  if (session.isError) return <div className="p-10 text-mist">Gagal memeriksa akun. <button onClick={() => void session.refetch()}>Coba lagi</button></div>
  if (!session.data?.user) return <Navigate replace to={`/login?next=${encodeURIComponent(location.pathname + location.search)}`} />
  return <Outlet />
}

export function App() {
  return (
    <Routes>
      <Route path="/" element={<Landing />} />
      <Route path="/login" element={<Login />} />
      <Route path="/register" element={<Register />} />
      <Route element={<RequireLogin />} >
      <Route path="/dashboard" element={<Dashboard />} />
      <Route path="/library" element={<Library />} />
      <Route path="/upload" element={<UploadStudio />} />
      <Route path="/rooms/new" element={<CreateRoom />} />
      <Route path="/join" element={<Join />} />
      <Route path="/j/:code" element={<QuickJoin />} />
      <Route path="/rooms/:code" element={<Lobby />} />
      <Route path="/watch/:code" element={<Suspense fallback={<div className="p-10 text-mist">Menyiapkan ruang nonton…</div>}><WatchRoom /></Suspense>} />
      <Route path="/profile" element={<Profile />} />
      <Route path="/admin" element={<Admin />} />
      </Route>
    </Routes>
  )
}
