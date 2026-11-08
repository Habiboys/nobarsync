# Database

PostgreSQL 16. Primary keys are UUIDs. Timestamps are `utc_datetime_usec`.

Main tables: `users`, `sessions`, `guest_identities`, `media_assets`, `media_variants`, `media_subtitles`, `upload_sessions`, `rooms`, `room_members`, `invitations`, `playlist_items`, `playlist_votes`, `room_playback_snapshots`, `playback_events`, `room_messages`, `room_reactions`, `room_ready_checks`, `room_leases`, `audit_logs`, plus Oban tables.

`room_members` has a check that exactly one of `user_id` and `guest_identity_id` is set, and partial unique indexes for one active membership per identity. Room codes are 6 characters from an alphabet without `0`, `O`, `1`, and `I`.

`room_playback_snapshots.room_id` is the primary key. `revision` increases on each accepted command. `room_leases` stores the node name and a fencing token so a second coordinator cannot own the room while the lease is valid.

Sessions store the SHA-256 of the cookie token, not the token. Audit rows record the action and resource, not secrets.
