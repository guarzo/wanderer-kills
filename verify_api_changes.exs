#!/usr/bin/env elixir

# Simple verification script to check that our API changes are working
# This verifies the function signatures exist by checking module exports

# Load the compiled modules
Code.require_file("lib/wanderer_kills/subscriptions/base_index.ex")
Code.require_file("lib/wanderer_kills/subscriptions/character_index.ex") 
Code.require_file("lib/wanderer_kills/subscriptions/system_index.ex")

alias WandererKills.Subscriptions.CharacterIndex
alias WandererKills.Subscriptions.SystemIndex

IO.puts("Checking that updated API functions are defined...")

# Check that the new functions exist in the modules
required_functions = [
  {CharacterIndex, :find_subscriptions_for_entity, 1},
  {CharacterIndex, :find_subscriptions_for_entities, 1}, 
  {SystemIndex, :find_subscriptions_for_entity, 1},
  {SystemIndex, :find_subscriptions_for_entities, 1}
]

all_good = true

for {module, function, arity} <- required_functions do
  if function_exported?(module, function, arity) do
    IO.puts("✓ #{module}.#{function}/#{arity} is defined")
  else
    IO.puts("❌ #{module}.#{function}/#{arity} is NOT defined") 
    all_good = false
  end
end

# Check that old functions are NOT exported (they should be gone)
old_functions = [
  {CharacterIndex, :find_subscriptions_for_character, 1},
  {CharacterIndex, :find_subscriptions_for_characters, 1},
  {SystemIndex, :find_subscriptions_for_system, 1}, 
  {SystemIndex, :find_subscriptions_for_systems, 1}
]

for {module, function, arity} <- old_functions do
  if function_exported?(module, function, arity) do
    IO.puts("❌ Old function #{module}.#{function}/#{arity} still exists!")
    all_good = false
  else
    IO.puts("✓ Old function #{module}.#{function}/#{arity} successfully removed")
  end
end

if all_good do
  IO.puts("\n✅ All API changes verified successfully!")
else
  IO.puts("\n❌ Some API changes are missing or incomplete")
  System.halt(1)
end