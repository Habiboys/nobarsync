# Deployment

## Local production images

```sh
export SECRET_KEY_BASE=$(openssl rand -base64 48)
export MEDIA_TOKEN_SECRET=$(openssl rand -base64 32)
docker compose -f docker-compose.prod.yml up --build
```

The API container migrates before it serves. The worker container does not migrate. The edge container is Caddy serving the Vite build and proxying `/api`, `/socket`, `/media`, and `/health` to the API. This file still starts MinIO. The public `minio/minio` and `quay.io/minio/minio` images no longer pull anonymously, so Compose uses `cgr.dev/chainguard/minio` and `cgr.dev/chainguard/minio-client`. Compose reads `S3_SCHEME`, `S3_HOST`, `S3_PORT`, `S3_REGION`, and `S3_PUBLIC_*` from the environment, defaulting to that MinIO. For R2, set those to the account S3 endpoint (`https://<ACCOUNT_ID>.r2.cloudflarestorage.com`, port 443, region `auto`) and put the R2 API token in `S3_ACCESS_KEY` / `S3_SECRET_KEY`. The browser uploads with the public endpoint, so the bucket CORS policy must allow the site origin and expose `ETag`. Playback stays on the local gateway until the media Worker is deployed with the same `MEDIA_TOKEN_SECRET`.

For a public host, change `infra/caddy/Caddyfile.prod` to a site block with your domain so Caddy can fetch a certificate. Set `PHX_SCHEME=https`, `FORCE_SECURE_COOKIES=true`, and `WEB_ORIGIN` to that origin.

## Worker

```sh
cd infra/cloudflare/media-worker
npx wrangler r2 bucket create nobarsync
npx wrangler secret put MEDIA_TOKEN_SECRET
npx wrangler deploy
```

The secret must match the API. This repository's tests do not call Cloudflare.

## Backup

`pg_dump` the database. Object storage is the media copy of record. After restoring Postgres, unfinished `processing` rows can be requeued. The worker deletes scratch on the way out; a killed encode is retried by Oban up to 5 times.

## Shutdown

The coordinator traps a terminate and writes `room_playback_snapshots`. An empty open room is closed by the maintenance cron after `empty_ttl_seconds` (default 600).
