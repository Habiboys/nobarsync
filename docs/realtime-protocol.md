# Realtime protocol

Topic: `room:<room_uuid>`. The short room code is not the topic.

Join requires a member. The join reply is the playback snapshot:

```json
{
  "v": 1,
  "room_id": "uuid",
  "revision": 3,
  "media_id": "uuid",
  "duration_ms": 8000,
  "control_mode": "host_only",
  "buffering_mode": "independent",
  "server_wall_ms": 1700000000000,
  "effective_at_ms": 1700000001200,
  "state": {
    "status": "paused",
    "anchor_position_ms": 1000,
    "anchor_server_time_ms": 1700000000000,
    "playback_rate": 1.0
  },
  "pending": {
    "status": "playing",
    "anchor_position_ms": 1000,
    "anchor_server_time_ms": 1700000001200,
    "playback_rate": 1.0
  }
}
```

Clients keep `state` until `serverNow >= effective_at_ms`, then apply `pending`. Older revisions are ignored.

## Client to server

- `clock.ping` `{ "t0": <performance.now> }` replies `{ "t0", "server_wall_ms" }`.
- `playback.play`, `playback.pause`, `playback.seek` `{ "v": 1, "request_id", "position_ms", "rtt_ms" }`.
- `playback.countdown` schedules play with a 3000 ms lead.
- `playback.heartbeat` `{ "drift_ms", "buffer_ms", "duration_ms" }` is metrics only.
- `player.ready`, `player.buffering`.
- `chat.send` `{ "body" }`, `reaction.send` `{ "emoji" }`.

## Server to client

- `playback.state` after every accepted command.
- `room.presence` with a Presence list.
- `room.media_changed`, `room.settings_changed`, `room.host_changed`.
- `chat.message`, `reaction.broadcast`.
- `room.error`.

Socket auth is a Phoenix token from `POST /api/v1/auth/socket-token`, max age 120 seconds. The client refreshes it by reconnecting.

## Clock

`offset = server_wall_ms - (t0 + rtt / 2)`. The client keeps the lowest-RTT sample and refreshes it. `Date.now()` is not the playback clock. `serverNow = performance.now() + offset`.

## Drift

`drift = actualMediaTime - target`. At or under 200 ms, do nothing. From 200 to 1500 ms, set a local playback rate of 0.97 or 1.04. Over 1500 ms, hard-seek, with a cooldown. That local rate is not written back as the room `playback_rate`, which stays 1.0.
