# NobarSync implementation update — 2026-11-08

Implementation work continues in `C:\Project\nobarkan2`. Existing staged and unstaged project work has been preserved; this update does not create a commit or deploy to cloud.

## Playback and synchronization

- All players follow the same server clock and `effective_at_ms`. The former frontend early-start window (up to 800 ms before the server transition) is removed.
- HLS now loads while paused, including on the host. The previous `autoStartLoad: false` path could leave the host without segments while a viewer loaded and played.
- Host controls require a ready player. The server rejects play/countdown if its current host status is buffering. A host buffering event freezes the room immediately at the reported position; host readiness schedules a shared three-second restart. A slow viewer keeps independent behavior unless the configured room policy says otherwise.
- Heartbeats include actual position, paused state, buffering and duration. They report metrics instead of silently rewriting the authoritative timeline. Fresh playing samples are extrapolated to a common instant for signed lag badges.
- Each participant card shows buffering, stale status, synchronization, or signed seconds/minutes relative to the host. A viewer can sync locally; host can pause and align everyone, then restart together.
- Viewer volume/mute, quality, subtitles, theater mode and fullscreen remain available. Shared play/pause/seek controls are shown only to host/moderator.
- Clock samples refresh every 30 seconds and when returning to the tab. Socket credentials refresh every minute for reconnect. Rejoin restores snapshot and member identity/role, including guests. Playback token renewal uses current tokens for HLS requests; native HLS reloads the renewed manifest and restores the canonical position.
- YouTube uses the official IFrame API with custom local audio controls, lifecycle cleanup and error handling. Its synchronization precision and autoplay behavior remain subject to YouTube/browser limitations.

## Room and UI

- Dark cinematic landing, dashboard hero and real room counters, responsive navigation, library cards and status filter/pagination, Upload Studio, account forms and admin job table.
- Chat stays alongside the player on desktop. Participants appear below the player in a responsive grid, suitable for a larger audience. On small screens the sections stack.
- Input/select/option backgrounds and text have explicit dark colors, including quality/subtitle choices.
- Persisted chat history, chat permissions, acknowledged send/error states, emoji reactions, readiness, copy invitation, playlist/voting, host transfer/kick, and room buffering settings are wired to backend endpoints.
- Profile supports display-name changes, avatar upload, password change with old-password verification and logout.
- HLS/player code loads on the watch route. Initial JS measured in the production build is about 333 KB raw / 104 KB gzip versus the earlier 968 KB raw / 304 KB gzip combined bundle. The watch route has a separate approximately 645 KB / 202 KB gzip chunk, largely HLS. These are build artifact sizes, not measured page-load latency or streaming throughput.
- Font imports include only the Latin Outfit styles actually used. No extra UI framework, remote artwork or call subsystem was added.

## Media pipeline

- Multipart uploads save part ETags and file identity per signed-in user in browser local storage. After pause/network failure/refresh, reselect the same file to continue acknowledged parts. Each part has bounded retries and a timeout. Abort cancels the upload session; paused uploads are retained for resumption while their server session remains valid (24 hours).
- The API checks session ownership/expiry, legal part numbers, contiguous expected part lists and actual completed object size before queueing encoding. A multipart ETag is not a cryptographic whole-file checksum.
- Encoder output uploads fail the job if required storage operations fail instead of incorrectly marking the media ready. Oban retries the same asset. Scratch cleanup remains in `after`; cancelled jobs do not re-enter encoding.
- Variant metadata refers to the actual `{label}.m3u8` output. Object deletion traverses paginated lists so long movies do not leave segments after the first storage page.
- URL imports and YouTube embeds are exposed separately. Processing status is polled only while Studio contains active processing assets. FFmpeg's no-upscale ladder remains in place.

## Reference comparison

Reference: https://github.com/Habiboys/frontend-nobarkan (main branch files read during this update).

| Reference feature | NobarSync implementation |
| --- | --- |
| Room creation/join/invite, close/delete, member kick | Available; watch/lobby UI connected |
| Live chat and media controls | Persisted chat, server timeline, local viewer audio |
| Movie management/search | Library search, status filtering, pagination, edit/delete and upload/import |
| Profile/password/avatar | Connected profile forms and password API |
| External video/extractor pages | Official YouTube embed and HTTPS direct import allowlist; arbitrary yt-dlp extraction is not introduced |
| Voice/video calling and call moderation | Excluded as requested |

This comparison follows the current Phoenix/HLS architecture rather than copying the reference application's backend API. Arbitrary extractors, Google Drive OAuth import and Cloudflare Stream are not enabled by this update. The existing design explicitly isolates/disables those integrations.

## Local use

1. Start services with `docker compose up -d --build` from the repository. Development site: `http://localhost:8080` (or Vite at `http://localhost:5173`).
2. Register/login, open Upload Studio, set a title and choose a video. If interrupted, reselect the same file and choose continue. Do not clear browser storage if the upload should resume.
3. Wait for processing to become ready, create a room and select a ready movie. Additional titles can be queued from the lobby.
4. Share `/j/{code}`. Guests can enter without an account. Host presses play or shared three-second countdown after loading completes.
5. Use participant badges to inspect lag. Viewers can select a lower quality or use local sync. Host can pause/align all, then restart together.

Configuration uses the existing `.env.example`: storage endpoint/credentials and `S3_PUBLIC_*` reachable from the browser, CORS exposing ETag, `MEDIA_TOKEN_SECRET`, database credentials, encoder concurrency/thread settings, and `IMPORT_HOST_ALLOWLIST` for direct imports. An empty import allowlist intentionally allows no URL sources. No credentials were changed.

For production use the existing `docker-compose.prod.yml` and `docs/deployment.md`. Cloudflare/R2 deployment, domains, secrets, Google OAuth and production traffic were not exercised or provisioned.

## Validation boundary

Frontend lint, production TypeScript/Vite build and backend `mix compile --warnings-as-errors` were used as static/build checks. ExUnit, Vitest, Playwright, load tests and manual multi-browser synchronization scenarios were intentionally not run per the user's request. No claim is made about measured drift, end-to-end playback correctness, throughput, browser coverage or cloud deployment. The testing/verification TODO remains pending; implementation TODO completion is not a claim that testing passed.
