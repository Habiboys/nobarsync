import { Socket } from "phoenix"

const count = Number(process.env.CLIENTS || 20)
const url = process.env.SOCKET_URL || "ws://localhost:4000/socket/websocket"
const token = process.env.SOCKET_TOKEN
const roomId = process.env.ROOM_ID

if (!token || !roomId) {
  console.error("Set SOCKET_TOKEN and ROOM_ID. This script measures channel connect time, not video drift.")
  process.exit(1)
}

const started = Date.now()
let open = 0
const sockets = []

for (let index = 0; index < count; index += 1) {
  const socket = new Socket(url, { params: { token } })
  sockets.push(socket)
  socket.connect()
  const channel = socket.channel(`room:${roomId}`, {})
  channel.join().receive("ok", () => {
    open += 1
    if (open === count) {
      console.log(JSON.stringify({ clients: count, joined: open, elapsed_ms: Date.now() - started }))
    }
  })
}

setTimeout(() => {
  console.log(JSON.stringify({ clients: count, joined: open, elapsed_ms: Date.now() - started, note: "protocol only" }))
  sockets.forEach((socket) => socket.disconnect())
  process.exit(open === count ? 0 : 1)
}, 20000)
