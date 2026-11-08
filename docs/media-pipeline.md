# Media pipeline

Uploads use S3 multipart. The API returns a presigned part URL. The browser PUTs the part to MinIO or R2. Completion stores the multipart ETag as the checksum and enqueues `NobarSync.Media.EncodeWorker`.

FFmpeg writes fMP4 HLS, H.264, AAC, 4 second segments, and GOP aligned to about 4 seconds. The ladder does not upscale: 1080p sources get 1080/720/480, 720p sources get 720/480, 480p sources get 480 only. Scratch files live under the system temp directory and are deleted on success, failure, and cancel.

Object keys:

- `videos/{id}/source/original.bin`
- `videos/{id}/hls/master.m3u8` and `{label}.m3u8`
- `videos/{id}/hls/{label}/init.mp4` and `segment_*.m4s`
- `videos/{id}/subtitles/{lang}-{index}.vtt`
- `videos/{id}/thumbnails/poster.webp`
- `videos/{id}/metadata.json`

The playback token is `base64url(canonical JSON) + "." + base64url(HMAC-SHA256)`. Canonical key order is `exp`, `media_id`, `prefix`, `room_id`, `scope`. The local gateway and `infra/cloudflare/media-worker` both reject expired tokens, other prefixes, and `..` before reading storage. The cache key is the object path, not the token.

YouTube assets store an id and are played with the IFrame Player API. Nothing is downloaded. Google Drive returns a disabled error. Cloudflare Stream returns `not_implemented`.

URL import allows only HTTPS hosts on `IMPORT_HOST_ALLOWLIST`, follows at most 3 redirects, and rejects private, loopback, and link-local addresses, including `169.254.169.254`. An empty allowlist allows nothing.
