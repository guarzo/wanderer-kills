FROM hexpm/elixir:1.18.3-erlang-25.3-debian-slim AS build

RUN apt-get update && \
    apt-get install -y build-essential git curl && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY mix.exs mix.lock ./
RUN mix local.hex --force && mix local.rebar --force
RUN MIX_ENV=prod mix deps.get --only prod && MIX_ENV=prod mix deps.compile

COPY lib lib
COPY config config

RUN MIX_ENV=prod mix compile

FROM debian:stable-slim AS app
RUN apt-get update && apt-get install -y ca-certificates && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=build /app/_build/prod/rel/wanderer_kills ./

ENV REPLACE_OS_VARS=true \
    MIX_ENV=prod

EXPOSE 4004
CMD ["bin/wanderer_kills", "start"] 