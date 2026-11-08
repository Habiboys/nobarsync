# Architecture

NobarSync uses one playback authority and distributed media.

- `apps/api` is a Phoenix 1.8 API. HTTP, channels, presence, and room coordinators run when `NOBARSYNC_ROLE` is `api` or `all`.
- The same image runs as `worker` and consumes the Oban `encode` queue. It does not start coordinators.
- Encode progress uses `pg_notify`. The API listens and republishes on `user:<owner_id>`. There is no Redis and no cluster.
- `apps/web` is the React client. It sends intents. It does not write the room timeline from `<video>` events.
- Objects live in a private bucket. The browser fetches them from `/media/t/{token}/...` or from the Cloudflare Worker with the same token.

A later second Phoenix node would take a room only by acquiring `room_leases`. This build runs one API node.

## Contexts

`Accounts`, `Media`, `WatchRooms`, `Playback`, `Realtime` (channels and presence), `Messaging`, and `Analytics`.

## Time

While a coordinator lives, elapsed playback uses the monotonic clock. Snapshots store a wall-clock anchor. After a restart the process recomputes the position from that anchor and rebinds the monotonic clock.
