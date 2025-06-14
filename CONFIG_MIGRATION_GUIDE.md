# Configuration Migration Guide

This guide helps migrate from the custom `WandererKills.Core.Config` module to standard Elixir configuration patterns.

## Migration Patterns

### 1. Compile-time Configuration (Preferred)

For configuration that doesn't change at runtime, use `Application.compile_env/3`:

```elixir
# Before
def timeout do
  Config.get([:http, :timeout], 5000)
end

# After (at module level)
@timeout Application.compile_env(:wanderer_kills, [:http, :timeout], 5000)

def timeout do
  @timeout
end
```

### 2. Runtime Configuration

For configuration that may change or needs runtime evaluation:

```elixir
# Before
def start_redisq? do
  Config.get([:services, :start_redisq], true)
end

# After
def start_redisq? do
  services = Application.get_env(:wanderer_kills, :services, [])
  Keyword.get(services, :start_redisq, true)
end
```

### 3. Common Migrations

| Old Pattern | New Pattern |
|------------|------------|
| `Config.cache().killmails_ttl` | `Application.compile_env(:wanderer_kills, [:cache, :killmails_ttl], 3600)` |
| `Config.get([:esi, :base_url])` | `Application.compile_env(:wanderer_kills, [:esi, :base_url], "default")` |
| `Config.app().http_client` | `Application.get_env(:wanderer_kills, :http, [])[:client]` |
| `Config.timeouts().default_request_ms` | `Application.compile_env(:wanderer_kills, [:http, :default_timeout_ms], 10_000)` |

### 4. Module-specific Examples

#### HTTP Client
```elixir
# Add at module level
@default_timeout_ms Application.compile_env(:wanderer_kills, [:http, :default_timeout_ms], 10_000)
@max_retries Application.compile_env(:wanderer_kills, [:http, :retry, :max_retries], 3)
```

#### ESI Client
```elixir
# Add at module level
@base_url Application.compile_env(:wanderer_kills, [:esi, :base_url], "https://esi.evetech.net/latest")
@request_timeout Application.compile_env(:wanderer_kills, [:esi, :request_timeout_ms], 30_000)
```

#### Cache Module
```elixir
# For dynamic namespace TTLs
defp get_ttl(namespace) do
  cache_config = Application.get_env(:wanderer_kills, :cache, [])
  
  case namespace do
    :killmails -> Keyword.get(cache_config, :killmails_ttl, 3600) * 1000
    :systems -> Keyword.get(cache_config, :system_ttl, 1800) * 1000
    # etc...
  end
end
```

### 5. Constants and Computed Values

Keep using the simplified `WandererKills.Config` module for:
- Application constants (max IDs, limits)
- Computed values (endpoint port)
- Common runtime checks (start_redisq?)

```elixir
# These remain in WandererKills.Config
WandererKills.Config.max_killmail_id()
WandererKills.Config.endpoint_port()
WandererKills.Config.start_redisq?()
```

## Migration Steps

1. **Identify usage patterns** - Check if config is used at compile-time or runtime
2. **Add module attributes** - For compile-time config, add `@config_value Application.compile_env(...)`
3. **Update function bodies** - Replace `Config.get()` calls with module attributes or runtime lookups
4. **Remove Config alias** - Change `alias WandererKills.Core.Config` to `alias WandererKills.Config`
5. **Test thoroughly** - Ensure configuration still works in all environments

## Benefits

- **Performance**: Compile-time configuration is resolved at compilation, not runtime
- **Clarity**: Standard Elixir patterns are more familiar to developers
- **Type Safety**: Dialyzer can better analyze compile-time values
- **Simplicity**: Less abstraction, more direct configuration access