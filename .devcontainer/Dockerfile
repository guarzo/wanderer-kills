FROM elixir:1.18.3-otp-27-slim

# Install development dependencies and Node.js in a single layer
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
    && curl -fsSL https://deb.nodesource.com/setup_23.x | bash - \
    && apt-get install -y nodejs \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && npm install -g npm@latest @anthropic-ai/claude-code

# Setup Elixir tools
RUN mix local.hex --force && mix local.rebar --force

WORKDIR /app
