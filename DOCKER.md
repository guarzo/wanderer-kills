# Docker Configuration

This project uses a consolidated Docker setup to minimize duplication and ensure consistency between development and production environments.

## Files Overview

### Production (`Dockerfile` + `docker-compose.yml`)

- **Purpose**: Production-ready container with optimized build
- **Base Image**: `hexpm/elixir:1.18.3-erlang-25.3-debian-slim`
- **Build**: Multi-stage build for smaller final image
- **Runtime**: Debian slim with only necessary runtime dependencies

### Development (`.devcontainer/`)

- **Purpose**: Development environment with full tooling
- **Base Image**: Same as production for consistency
- **Features**: Additional development tools (vim, jq, net-tools, etc.)
- **Volumes**: Source code mounted for live editing

## Common Patterns

Both configurations share:

- **Base Image**: `hexpm/elixir:1.18.3-erlang-25.3-debian-slim`
- **Core Dependencies**: `build-essential`, `git`, `curl`, `ca-certificates`
- **Elixir Setup**: `mix local.hex --force && mix local.rebar --force`
- **Package Management**: `apt-get` with `--no-install-recommends` and cleanup

## Usage

### Production

```bash
# Build and run production container
docker-compose up --build

# Or build manually
docker build -t wanderer-kills .
docker run -p 4004:4004 wanderer-kills
```

### Development

Use VS Code with the Dev Containers extension, or:

```bash
# Run development environment
cd .devcontainer
docker-compose up --build
```

## Maintenance

When updating Docker configurations:

1. Keep base images consistent between production and development
2. Use the same package installation patterns
3. Update both Dockerfiles if changing core dependencies
4. Test both production and development builds
5. Update this documentation if adding new patterns
