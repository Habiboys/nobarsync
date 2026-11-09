import { Link } from "react-router"

export function Brand() {
  return (
    <Link className="brand" to="/dashboard" aria-label="Manonton, beranda">
      <img src="/manonton.png" alt="" />
    </Link>
  )
}
