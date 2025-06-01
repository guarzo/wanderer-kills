FROM elixir:otp-27

RUN apt install -yq curl gnupg
RUN apt-get update && apt-get install -y --no-install-recommends \
    sudo \
    curl \
    make \
    git \
    bash \
    build-essential \
    ca-certificates \
    jq \
    vim \
    net-tools \
    procps \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

RUN apt --fix-broken install

RUN mix local.hex --force

WORKDIR /app
