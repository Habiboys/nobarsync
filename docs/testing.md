# Testing

## Unit

`apps/api/test/nobarsync/playback` covers the timeline, command lead, authorization, supersession, and buffering policy. `playback_token_test.exs` covers the HMAC token. `apps/web/src/sync.test.ts` covers the client offset, the effective-at switch, and drift hysteresis. The Worker tests cover the same canonical JSON and a request that caches by object key.

## Integration

`auth_controller_test.exs` covers register, login, me, forbidden admin, invalid login, and guest. `coordinator_test.exs` covers play, idempotent request ids, a rejected viewer command, and snapshot restore. `room_channel_test.exs` covers join and `clock.ping`.

Media tests that need MinIO and a generated fixture are run with the compose stack. A multi-gigabyte upload is not part of CI. The same 8 MiB part protocol is what the studio uses; the size cap is `MAX_UPLOAD_BYTES` (default 8 GiB) and is not itself a test result.

## Browser

Playwright lives in `tests/e2e`. Chromium is the gate. Firefox and WebKit are smoke checks when those browsers are installed. Drift must be read from `video.currentTime` or the YouTube player, not from a simulated socket.

## Load

`tests/load/clients.mjs` opens Phoenix channels. It reports connect time. It does not report media drift. Start with 20 clients. Try 100 and 500 only if the machine stays responsive, and record the hardware.
