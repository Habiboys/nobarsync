import { Link } from "react-router"

export function Brand() {
  return <Link className="brand" to="/dashboard" aria-label="Manonton, beranda">manonton<span aria-hidden="true">.</span></Link>
}
