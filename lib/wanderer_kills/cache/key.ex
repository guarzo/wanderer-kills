defmodule WandererKills.Cache.Key do
  @moduledoc """
  Module for managing cache keys and TTLs.

  This module provides functions for generating and validating cache keys,
  as well as managing TTLs for different types of cached data.

  ## Features

  - Cache key generation with DRY macros
  - TTL management
  - Key validation

  ## Configuration

  Cache TTLs are managed through application config:

  ```elixir
  config :wanderer_kills,
    cache: %{
      killmails: [name: :killmails_cache, ttl: :timer.hours(24)],
      system: [name: :system_cache, ttl: :timer.hours(1)],
      esi: [name: :esi_cache, ttl: :timer.hours(48)]
    }
  ```
  """

  @prefix "wanderer_kills"

  @type cache_type :: :killmails | :system | :esi | :corporation | :character | :alliance
  @type cache_key :: String.t()
  @type cache_value :: term()

  @doc """
  Generates a cache key for the given cache type and parameters.

  ## Parameters
  - `cache_type` - The type of cache (:killmails, :system, or :esi)
  - `parts` - List of key parts to join

  ## Returns
  A formatted cache key string.

  ## Example

  ```elixir
  key = generate(:killmails, ["killmail", "123"])
  # "wanderer_kills:killmails:killmail:123"
  ```
  """
  @spec generate(cache_type(), [String.t()]) :: cache_key()
  def generate(cache_type, parts) do
    [@prefix, Atom.to_string(cache_type) | parts]
    |> Enum.join(":")
  end

  @doc """
  Gets the TTL for a given cache type.

  ## Parameters
  - `cache_type` - The type of cache (:killmails, :system, or :esi)

  ## Returns
  The TTL in milliseconds.

  ## Example

  ```elixir
  ttl = get_ttl(:killmails)
  # 86400000
  ```
  """
  @spec get_ttl(cache_type()) :: pos_integer()
  def get_ttl(cache_type) do
    WandererKills.Core.Config.cache(cache_type)[:ttl] || 3600
  end

  @doc """
  Validates a cache key format.

  ## Parameters
  - `key` - The cache key to validate

  ## Returns
  - `true` if the key is valid
  - `false` otherwise

  ## Example

  ```elixir
  valid? = validate_key("wanderer_kills:killmails:killmail:123")
  # true
  ```
  """
  @spec validate_key(cache_key()) :: boolean()
  def validate_key(key) do
    case String.split(key, ":") do
      [@prefix, _cache_type | _parts] -> true
      _ -> false
    end
  end

  # Killmail cache keys

  @doc """
  Generates a cache key for a killmail.
  """
  def killmail_key(killmail_id) do
    generate(:killmails, [to_string(killmail_id)])
  end

  @doc """
  Generates a key for the list of all killmail IDs.
  """
  def killmail_ids_key() do
    generate(:killmails, ["killmail_ids"])
  end

  # System cache keys

  @doc """
  Generates a cache key for system data.
  """
  def system_data_key(system_id) do
    generate(:system, [to_string(system_id), "data"])
  end

  @doc """
  Generates a key for the list of active systems.
  """
  @spec active_systems_key() :: cache_key()
  def active_systems_key() do
    generate(:system, ["active"])
  end

  @doc """
  Generates a key for a system's kill count.
  """
  def system_kill_count_key(system_id) do
    generate(:killmails, ["system", to_string(system_id), "kill_count"])
  end

  @doc """
  Generates a key for a system's fetch timestamp.
  """
  def system_fetch_timestamp_key(system_id) do
    generate(:killmails, ["system", to_string(system_id), "fetch_timestamp"])
  end

  @doc """
  Generates a key for a system's TTL.
  """
  def system_ttl_key(system_id) do
    generate(:system, [to_string(system_id), "ttl"])
  end

  # ESI cache keys

  @doc """
  Generates a cache key for type info.
  """
  @spec type_info_key(integer()) :: cache_key()
  def type_info_key(type_id) do
    generate(:esi, ["type", to_string(type_id)])
  end

  @doc """
  Generates a cache key for group info.
  """
  @spec group_info_key(integer()) :: cache_key()
  def group_info_key(group_id) do
    generate(:esi, ["group", to_string(group_id)])
  end

  @doc """
  Generates a cache key for character info.
  """
  @spec character_info_key(integer()) :: cache_key()
  def character_info_key(character_id) do
    generate(:character, [to_string(character_id), "info"])
  end

  @doc """
  Generates a cache key for corporation info.
  """
  @spec corporation_info_key(integer()) :: cache_key()
  def corporation_info_key(corporation_id) do
    generate(:corporation, [to_string(corporation_id), "info"])
  end

  @doc """
  Generates a cache key for alliance info.
  """
  @spec alliance_info_key(integer()) :: cache_key()
  def alliance_info_key(alliance_id) do
    generate(:alliance, [to_string(alliance_id), "info"])
  end

  @doc """
  Generates a key for a system's killmails or killmail IDs.

  ## Parameters
  - `system_id` - The system ID
  - `type` - Either `:killmails` (default) or `:killmail_ids`

  ## Examples
      iex> system_killmails_key(123)
      "killmails:system:123"

      iex> system_killmails_key(123, :killmail_ids)
      "killmails:system:123:killmail_ids"
  """
  def system_killmails_key(system_id, type \\ :killmails) do
    case type do
      :killmails -> generate(:killmails, ["system", to_string(system_id)])
      :killmail_ids -> generate(:killmails, ["system", to_string(system_id), "killmail_ids"])
    end
  end

  @doc """
  Generates a key for a system's killmail IDs.

  This function is kept for backward compatibility.
  Use `system_killmails_key(system_id, :killmail_ids)` instead.
  """
  def system_killmail_ids_key(system_id) do
    system_killmails_key(system_id, :killmail_ids)
  end

  @doc """
  Alias for system_fetch_timestamp_key/1 for backward compatibility.
  """
  def system_fetch_ts_key(system_id) do
    system_fetch_timestamp_key(system_id)
  end

  @doc """
  Generates a key for ESI rate limit tracking.
  """
  def esi_rate_limit_key do
    generate(:esi, ["rate_limit"])
  end

  @doc """
  Generates a key for ESI error tracking.
  """
  def esi_error_key do
    generate(:esi, ["error"])
  end

  @doc """
  Generates a key for ESI killmail tracking.
  """
  def esi_killmail_key(killmail_id) do
    generate(:esi, ["killmail", to_string(killmail_id)])
  end

  @doc """
  Generates a key for ESI system killmails tracking.
  """
  def esi_system_killmails_key(system_id) do
    generate(:esi, ["system", to_string(system_id), "killmails"])
  end

  @doc """
  Generates a cache key for ESI character info.
  """
  @spec esi_character_info_key(integer()) :: cache_key()
  def esi_character_info_key(character_id) do
    generate(:esi, ["character", to_string(character_id)])
  end

  @doc """
  Generates a key for ESI corporation info tracking.
  """
  @spec esi_corporation_info_key(integer()) :: cache_key()
  def esi_corporation_info_key(corporation_id) do
    generate(:esi, ["corporation", to_string(corporation_id)])
  end

  @doc """
  Generates a cache key for ESI alliance info.
  """
  @spec esi_alliance_info_key(integer()) :: cache_key()
  def esi_alliance_info_key(alliance_id) do
    generate(:esi, ["alliance", to_string(alliance_id)])
  end

  @doc """
  Generates a key for a character's killmails.
  """
  def character_killmails_key(character_id) do
    generate(:killmails, ["character", to_string(character_id)])
  end

  @doc """
  Generates a key for a corporation's killmails.
  """
  def corporation_killmails_key(corporation_id) do
    generate(:killmails, ["corporation", to_string(corporation_id)])
  end

  @doc """
  Generates a key for an alliance's killmails.
  """
  def alliance_killmails_key(alliance_id) do
    generate(:killmails, ["alliance", to_string(alliance_id)])
  end

  @doc """
  Generates a cache key for system info.
  """
  @spec system_info_key(integer()) :: cache_key()
  def system_info_key(system_id) do
    generate(:system, [to_string(system_id), "info"])
  end
end
