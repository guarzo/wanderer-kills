# Domain Struct Migration Guide

This guide explains how to migrate from using plain maps to domain structs for killmail data.

## Overview

We've introduced typed domain structs to replace loose maps for killmail data:

- `WandererKills.Domain.Killmail` - Main killmail struct
- `WandererKills.Domain.Victim` - Victim information
- `WandererKills.Domain.Attacker` - Attacker information
- `WandererKills.Domain.ZkbMetadata` - zKillboard metadata

## Benefits

1. **Type Safety** - Compile-time guarantees about data structure
2. **Documentation** - Clear field definitions with types
3. **Validation** - Built-in validation during struct creation
4. **Refactoring** - Easier to change data structure safely
5. **Performance** - Struct access is faster than map access

## Usage

### Enabling Structs in Processing

The `UnifiedProcessor` now accepts a `:use_structs` option:

```elixir
# Process single killmail with structs
{:ok, killmail} = UnifiedProcessor.process_killmail(
  killmail_data,
  cutoff_time,
  use_structs: true
)

# Process batch with structs
{:ok, killmails} = UnifiedProcessor.process_batch(
  killmail_list,
  cutoff_time,
  use_structs: true
)
```

### Working with Killmail Structs

```elixir
# Access fields directly
killmail.killmail_id
killmail.system_id
killmail.victim.ship_type_id

# Check if victim is NPC
WandererKills.Domain.Victim.npc?(killmail.victim)

# Find final blow attacker
final_blow = WandererKills.Domain.Attacker.find_final_blow(killmail.attackers)

# Access zkb metadata
if killmail.zkb do
  value = WandererKills.Domain.ZkbMetadata.value(killmail.zkb)
  solo = WandererKills.Domain.ZkbMetadata.solo_kill?(killmail.zkb)
end
```

### Converting Between Formats

```elixir
# Struct to map (for JSON serialization)
map = WandererKills.Domain.Killmail.to_map(killmail)

# Map to struct
{:ok, killmail} = WandererKills.Domain.Killmail.new(killmail_map)
```

## Migration Strategy

### Phase 1: Opt-in Usage (Current)
- Add `:use_structs` option to processing functions
- New code can use structs
- Existing code continues using maps
- Storage layer continues using maps

### Phase 2: Gradual Adoption
- Update internal processing to use structs
- Convert at boundaries (API input/output)
- Add struct support to more modules

### Phase 3: Full Migration
- Make structs the default
- Convert all internal code
- Only convert to maps for:
  - JSON serialization
  - ETS/storage layer
  - External API calls

## Code Patterns

### Pattern Matching

```elixir
# Works with both formats
def process_killmail(%Killmail{} = killmail) do
  # Struct version
  killmail.killmail_id
end

def process_killmail(killmail) when is_map(killmail) do
  # Map version (fallback)
  killmail["killmail_id"]
end
```

### Storage Compatibility

The storage layer continues to use maps for compatibility:

```elixir
# Automatically converts struct to map for storage
defp store_killmail_async(killmail) do
  killmail_map = ensure_map(killmail)
  KillmailStore.put(killmail_map["killmail_id"], system_id, killmail_map)
end

defp ensure_map(%Killmail{} = killmail), do: Killmail.to_map(killmail)
defp ensure_map(map) when is_map(map), do: map
```

## Testing

When testing with structs:

```elixir
# Create test data as structs
{:ok, killmail} = Killmail.new(%{
  "killmail_id" => 123,
  "kill_time" => "2024-01-01T12:00:00Z",
  "system_id" => 30000142,
  "victim" => %{"ship_type_id" => 671},
  "attackers" => []
})

# Assertions work naturally
assert killmail.killmail_id == 123
assert killmail.victim.ship_type_id == 671
```

## Next Steps

1. Start using `:use_structs => true` in new code
2. Update tests to use structs
3. Gradually migrate internal processors
4. Consider making structs the default in a future release

The struct-based approach provides better type safety and documentation while maintaining backward compatibility with the existing map-based system.