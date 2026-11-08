# Limitations

- Sync is not frame-perfect. A p95 under 500 ms is a measurement target for a controlled network after warmup, not a guarantee. 200–300 ms is an optimization goal.
- Drift numbers come only from a real media element. A WebSocket load script does not measure drift.
- YouTube sync depends on the IFrame API. Seek and rate control are coarser than HLS, and autoplay can be blocked.
- Safari uses native HLS. The token stays in the path so relative playlist URLs keep working. Custom request headers are not required.
- Broadcast, live HLS, WebRTC SFU, picture-in-picture as a product mode, theater ambience, timestamped reactions, per-title watch history, and scheduled parties are not built.
- Voice chat is not included.
- A closed room does not replace a license for the video.
- The URL importer buffers the response in memory, up to `IMPORT_MAX_BYTES`.
- Guest mutations are not CSRF-protected. Session cookies are `SameSite=Lax`.
- Cost notes are estimates, not quotes. Cloudflare Stream list prices often cited for planning are about $1 per 1,000 delivery minutes and $5 per 1,000 storage minutes. R2 Standard is about $0.015 per GB-month before Worker requests and transcode time. This app does not calculate a bill.
- A starting VPS of 2–4 vCPU and 4–8 GB RAM is a starting point, not a capacity claim.
- Cloud R2 and a deployed Worker were not exercised in this environment. The Worker contract is covered by Vitest with an in-memory bucket.
