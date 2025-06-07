FROM hexpm/elixir:1.18.3-erlang-25.3-debian-slim

# Install development and build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    git \
    curl \
    ca-certificates \
    sudo \
    make \
    bash \
    jq \
    vim \
    net-tools \
    procps \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Setup Elixir tools
RUN mix local.hex --force && mix local.rebar --force

WORKDIR /app
