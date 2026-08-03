FROM elixir:1.19.5-otp-28-slim AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential git curl ca-certificates sudo make jq \
    && curl -fsSL https://deb.nodesource.com/setup_24.x -o /tmp/nodesource_setup.sh \
    && bash /tmp/nodesource_setup.sh \
    && rm -f /tmp/nodesource_setup.sh \
    && apt-get install -y nodejs \
    && mix local.hex --force && mix local.rebar --force \
    && npm install -g npm@latest @anthropic-ai/claude-code \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY mix.exs mix.lock ./
RUN mix deps.get && mix deps.compile

COPY . .

FROM elixir:1.19.5-otp-28-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
      bash zsh vim nano git curl wget ca-certificates \
      build-essential make jq htop tree zip unzip \
      net-tools procps iputils-ping telnet \
    && curl -fsSL https://deb.nodesource.com/setup_24.x -o /tmp/nodesource_setup.sh \
    && bash /tmp/nodesource_setup.sh \
    && rm -f /tmp/nodesource_setup.sh \
    && apt-get install -y nodejs \
    && npm install -g npm@latest @anthropic-ai/claude-code \
    && apt-get clean && rm -rf /var/lib/apt/lists/* \
    && useradd -m -s /usr/bin/zsh vscode && mkdir /app && chown vscode:vscode /app

USER vscode
WORKDIR /app

COPY --chown=vscode:vscode --from=builder /app /app

# Deliberately no `ENV MIX_ENV=dev`: Mix already defaults to :dev, and an
# exported MIX_ENV overrides the `preferred_envs` in mix.exs, which made plain
# `mix test` run in :dev where test-only deps such as :mox are not available.
ENV ERL_AFLAGS="-kernel shell_history enabled"


