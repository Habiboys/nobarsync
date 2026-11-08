# NobarSync

NobarSync is a watch-together app. Viewers load video from object storage or an official YouTube embed. One room coordinator on the server owns play, pause, seek, and media changes.

## Architecture

The Phoenix API stores accounts, rooms, and playback snapshots in PostgreSQL. A `RoomCoordinator` process per open room is the playback authority. Video bytes are not proxied through that process. Uploads go to MinIO or R2 with signed multipart URLs. An Oban worker in a separate container runs FFmpeg and writes HLS. A local gateway, or the Cloudflare Worker in `infra/cloudflare/media-worker`, checks a short HMAC token before serving objects.

See `docs/architecture.md`, `docs/realtime-protocol.md`, and `docs/media-pipeline.md`.

## Prerequisites

Docker with Compose, and a terminal. Elixir and Node are only needed outside Docker. Local development does not need a Cloudflare account.

## Local

```sh
docker compose up --build
```

Open `http://localhost:8080`. Seed accounts from `.env.example`:

- `admin@nobarsync.local` / `nobarsync-dev`
- `host@nobarsync.local` / `nobarsync-dev`

The API is also on `http://localhost:4000` and the Vite server on `http://localhost:5173`.

## Tests

```sh
docker compose up -d postgres
docker run --rm --network nobarkan2_default -v "$PWD/apps/api:/app" -w /app -e MIX_ENV=test -e POSTGRES_HOST=postgres nobarsync-dev sh -c "mix deps.get && mix test"
```

Frontend unit tests: `npm test` in `apps/web`. Worker token tests: `npm test` in `infra/cloudflare/media-worker`.

## Production shape

`docker compose -f docker-compose.prod.yml up --build` builds the Phoenix release and the static edge image. Fill `SECRET_KEY_BASE` and `MEDIA_TOKEN_SECRET`. MinIO is included so this stack can run without R2. For R2, point `S3_*` at the R2 S3 endpoint and deploy `infra/cloudflare/media-worker` with the same `MEDIA_TOKEN_SECRET`. That cloud deploy is documented in `docs/deployment.md` and is not claimed as verified here.

## Environment

Copy `.env.example`. The names there are the ones the API reads. Do not commit real keys.
