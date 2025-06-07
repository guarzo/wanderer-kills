FROM elixir:1.18.3-otp-27-slim AS build

# Install build dependencies (consistent with devcontainer)
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    git \
    curl \
    ca-certificates \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Setup Elixir tools and dependencies
COPY mix.exs mix.lock ./
RUN mix local.hex --force && mix local.rebar --force
RUN MIX_ENV=prod mix deps.get --only prod && MIX_ENV=prod mix deps.compile

COPY lib lib
COPY config config

RUN MIX_ENV=prod mix compile

FROM debian:stable-slim AS app
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=build /app/_build/prod/rel/wanderer_kills ./

ENV REPLACE_OS_VARS=true \
    MIX_ENV=prod

EXPOSE 4004
CMD ["bin/wanderer_kills", "start"] 