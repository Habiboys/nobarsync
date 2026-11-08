FROM elixir:1.18.4 AS build
RUN apt-get update \
  && apt-get install -y --no-install-recommends build-essential git ca-certificates \
  && rm -rf /var/lib/apt/lists/*
WORKDIR /app
ENV MIX_ENV=prod
COPY apps/api/mix.exs apps/api/mix.lock* ./
RUN mix local.hex --force && mix local.rebar --force && mix deps.get --only prod
COPY apps/api ./
RUN mix deps.compile && mix compile && mix release

FROM debian:bookworm-slim
RUN apt-get update \
  && apt-get install -y --no-install-recommends ffmpeg ca-certificates curl libssl3 libncurses6 \
  && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=build /app/_build/prod/rel/nobarsync ./
COPY infra/docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENV MIX_ENV=prod PHX_SERVER=true
EXPOSE 4000
ENTRYPOINT ["/entrypoint.sh"]
