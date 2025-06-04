# Code Review Feedback

## Critical Issues

### 1. Error Handling in Parser

**Location**: `lib/wanderer_kills/parser.ex` (lines 109-112)

**Issue**: The code assigns `system_id` from enriched map keys which may be nil, then calls `WandererKills.KillmailStore.insert_event` synchronously without error handling.

**Recommendation**:

1. Add a check to ensure `system_id` is not nil before calling `insert_event`
2. Change the call to be asynchronous or run it in a separate process/task to avoid blocking the parser
3. Add proper error handling to catch and log any failures from `insert_event` without crashing the parser

### 2. Deprecated PubSub Configuration

**Location**: `config/config.exs` (lines 174-175)

**Issue**: The Phoenix PubSub configuration uses the deprecated PG2 adapter.

**Recommendation**: Replace the adapter value from `Phoenix.PubSub.PG2` to `Phoenix.PubSub.PG` to use the modern PG adapter for improved performance and compatibility.

### 3. Configuration Documentation

**Location**: `config/config.exs` (lines 56-60)

**Issue**: Missing descriptive comments for configuration keys.

**Recommendation**: Add descriptive comments above each key in the killmail_store configuration to explain:

- What `gc_interval_ms` represents
- What `max_events_per_system` represents
- How these settings affect the killmail store behavior

## Performance Improvements

### 1. Event Fetching Optimization

**Location**: `lib/wanderer_kills/killmail_store.ex` (lines 126-201)

**Issue**: Current event fetching uses `:ets.foldl` which can be inefficient for large datasets.

**Recommendation**: Refactor the `fetch` and `fetch_one` functions to use `:ets.select` with appropriate match specifications that filter events by system_ids and event_id offsets. This will:

- Optimize event retrieval by leveraging ETS's built-in pattern matching
- Reduce the overhead of folding over all entries

## Code Organization

### 1. Error Handling Duplication

**Location**: `lib/wanderer_kills/web/api/killfeed_controller.ex` (lines 29-85, 100-149)

**Issue**: Error handling logic in the else clauses of `poll/2` and `next/2` functions is duplicated.

**Recommendation**: Extract common error handling into a private helper function that:

- Takes the error tuple and params
- Performs appropriate logging
- Sends the JSON response

### 2. Event Transformation

**Location**: `lib/wanderer_kills/web/api/killfeed_controller.ex` (lines 54-61)

**Issue**: Event transformation logic is embedded in an Enum.map.

**Recommendation**: Extract the transformation logic into a private helper function that:

- Takes an event tuple
- Returns the transformed map

### 3. Validation Error Handling

**Location**: `lib/wanderer_kills/web/api/killfeed_controller.ex` (lines 165-186)

**Issue**: Uses throw/catch for validation errors.

**Recommendation**: Replace with `Enum.reduce_while/3` for more idiomatic Elixir error handling:

- Iterate over systems list using `Enum.reduce_while`
- Validate each system ID
- Halt with error tuple if invalid ID found
- Accumulate valid IDs and return `{:ok, system_ids}`

## Best Practices

### 1. Configuration Management

**Issue**: Mix of runtime and compile-time configs

**Current**:

```elixir
# Good - compile time
@base_url Application.compile_env(:wanderer_kills, [:zkb, :base_url])

# Consider centralizing runtime configs
def config_value(key), do: Application.get_env(:wanderer_kills, key)
```

### 2. Magic Numbers & Constants

**Issue**: Scattered constants throughout the codebase

**Current**:

```elixir
ttl: :timer.hours(24)
max_retries: 3
backoff_ms: 1000
```

**Recommendation**: Centralize in a config module:

```elixir
defmodule WandererKills.Constants do
  def cache_ttl(:killmails), do: :timer.hours(24)
  def retry_config(:http), do: [max_retries: 3, backoff_ms: 1000]
end
```

### 3. GenServer Timeout Handling

**Issue**: No explicit timeouts found

**Recommendation**: Add explicit timeouts:

```elixir
GenServer.call(server, request, 30_000) # Explicit timeout
```

### 4. Documentation Gaps

**Issue**: Missing API documentation for public endpoints

**Recommendation**: Add OpenAPI/Swagger specs

## Security Recommendations

### 1. Request Validation

**Recommendation**: Add client ID validation:

```elixir
# In killfeed_controller.ex
defp validate_client_id(client_id) when byte_size(client_id) > 100 do
  {:error, :client_id_too_long}
end
```

### 2. Enhanced Monitoring

**Recommendation**: Add custom metrics:

```elixir
:telemetry.execute([:wanderer_kills, :cache, :hit], %{count: 1}, %{cache: :killmails})
```

### 3. Circuit Breaker Pattern

**Recommendation**: Implement for external API calls:

```elixir
defmodule WandererKills.CircuitBreaker do
  # Prevent cascade failures
end
```

🛡️ Secu
