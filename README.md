# WandererKills

A standalone service for retrieving and caching EVE Online killmails from zKillboard.

## Development Setup

### Using Docker Development Container

The project includes a development container configuration for a consistent development environment. To use it:

1. Install [Docker](https://docs.docker.com/get-docker/) and [VS Code](https://code.visualstudio.com/)
2. Install the [Remote - Containers](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers) extension in VS Code
3. Clone this repository
4. Open the project in VS Code
5. When prompted, click "Reopen in Container" or use the command palette (F1) and select "Remote-Containers: Reopen in Container"

The development container includes:

- Elixir 1.14.0
- OTP 25.0
- Redis for caching
- All required build tools

### Data Mounting

The service requires access to several data directories:

1. **Cache Directory**

   ```bash
   # Mount the cache directory for persistent caching
   docker run -v /path/to/cache:/app/cache wanderer-kills
   ```

2. **Log Directory**

   ```bash
   # Mount the log directory for persistent logs
   docker run -v /path/to/logs:/app/logs wanderer-kills
   ```

3. **Configuration Directory**
   ```bash
   # Mount a custom configuration directory
   docker run -v /path/to/config:/app/config wanderer-kills
   ```

### Ship-Type Data Bootstrap

The service requires ship type data for proper operation. To bootstrap the data:

1. **Automatic Bootstrap**

   ```bash
   # The service will automatically download and process ship type data on first run
   mix run --no-halt
   ```

2. **Manual Bootstrap**

   ```bash
   # Download and process ship type data manually
   mix run -e "WandererKills.Data.ShipTypeUpdater.update_all_ship_types()"
   ```

3. **Verify Data**
   ```bash
   # Check if ship type data is properly loaded
   mix run -e "IO.inspect(WandererKills.Data.ShipTypeInfo.get_ship_type(670))"
   ```

## Configuration

The service can be configured through environment variables or a config file:

```elixir
# config/config.exs
config :wanderer_kills,
  port: String.to_integer(System.get_env("PORT") || "4004"),
  cache: %{
    killmails: [name: :killmails_cache, ttl: :timer.hours(24)],
    system: [name: :system_cache, ttl: :timer.hours(1)],
    esi: [name: :esi_cache, ttl: :timer.hours(48)]
  }
```

## API Endpoints

- `GET /api/v1/killmails/:system_id` - Get killmails for a system
- `GET /api/v1/systems/:system_id/count` - Get kill count for a system
- `GET /api/v1/ships/:type_id` - Get ship type information

## Development

### Running Tests

```bash
mix test
```

### Code Quality

```bash
# Format code
mix format

# Run Credo
mix credo

# Run Dialyzer
mix dialyzer
```

### Docker Development

```bash
# Build the development image
docker build -t wanderer-kills-dev -f Dockerfile.dev .

# Run the development container
docker run -it --rm \
  -v $(pwd):/app \
  -p 4004:4004 \
  wanderer-kills-dev
```

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Logging

The application uses a standardized logging system with the following log levels:

- `:debug` - Detailed information for debugging purposes

  - Cache operations
  - Task completions
  - Request/response details
  - System state changes

- `:info` - General operational information

  - Successful API requests
  - Cache misses
  - System startup/shutdown
  - Background job completions

- `:warning` - Unexpected but handled situations

  - Rate limiting
  - Cache errors
  - Invalid input data
  - Retry attempts

- `:error` - Errors that affect operation but don't crash the system
  - API failures
  - Database errors
  - Task failures
  - Invalid state transitions

Each log entry includes:

- Request ID (for HTTP requests)
- Module name
- Operation context
- Relevant metadata

To configure logging levels, set the `:logger` configuration in your environment:

```elixir
config :logger,
  level: :info,
  metadata: [:request_id, :module, :function]
```
