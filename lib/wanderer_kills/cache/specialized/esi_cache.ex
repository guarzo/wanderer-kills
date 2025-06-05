defmodule WandererKills.Cache.Specialized.EsiCache do
  @moduledoc """
  Unified module for ESI (EVE Online ESI API) data fetching and caching.

  This module consolidates both API fetching and caching responsibilities,
  providing `get_*_info/1` functions that delegate to a unified `fetch_or_store/2`
  that handles key generation and TTL management.

  ## Features

  - ESI data fetching and caching
  - Unified TTL management
  - Automatic cache key generation
  - Comprehensive error handling
  - Typed structs for all ESI data

  ## Configuration

  ESI cache configuration is managed through application config:

  ```elixir
  config :wanderer_kills,
    cache: %{
      esi: [name: :esi_cache, ttl: :timer.hours(48)]
    },
    esi: [
      base_url: "https://esi.evetech.net/latest"
    ]
  ```

  ## Usage

  ```elixir
  # Get character info (will fetch from API if not cached)
  {:ok, character_info} = get_character_info(123)

  # Get type info
  {:ok, type_info} = get_type_info(456)
  ```
  """

  require Logger
  alias WandererKills.Cache.Base
  alias WandererKills.Cache.Key
  alias WandererKills.Config
  alias WandererKills.Esi.Data.Types
  alias WandererKills.Http.ClientProvider

  @doc """
  Generic helper function for ESI info fetching.

  This reduces boilerplate by providing a standardized way to:
  1. Generate cache key using Key module
  2. Build ESI URL
  3. Parse response using provided parser function
  4. Fetch or retrieve from cache

  ## Parameters
  - `key_fn` - Function to generate cache key (e.g., &Key.character_info_key/1)
  - `endpoint` - ESI endpoint pattern (e.g., "/characters")
  - `id` - The ID to fetch
  - `parser_fn` - Function to parse the API response

  ## Returns
  - `{:ok, parsed_data}` - On success
  - `{:error, reason}` - On failure
  """
  @spec fetch_esi_info((pos_integer() -> String.t()), String.t(), pos_integer(), (map() -> term())) ::
          {:ok, term()} | {:error, term()}
  def fetch_esi_info(key_fn, endpoint, id, parser_fn) do
    key = key_fn.(id)
    url = "#{base_url()}#{endpoint}/#{id}/"

    fetch_fn = fn -> handle_api_response(url, parser_fn) end
    fetch_or_store(key, fetch_fn)
  end

  @type type_id :: pos_integer()
  @type group_id :: pos_integer()
  @type character_id :: pos_integer()
  @type corporation_id :: pos_integer()
  @type alliance_id :: pos_integer()
  @type system_id :: pos_integer()
  @type cache_status :: :ok | {:error, term()}

  @doc """
  Base URL for ESI API.
  """
  def base_url do
    Config.esi().base_url
  end

  @doc """
  Unified fetch or store function that handles key generation and TTL.
  """
  @spec fetch_or_store(String.t(), (-> {:ok, term()} | {:error, term()})) ::
          {:ok, term()} | {:error, term()}
  def fetch_or_store(key, fetch_fn) when is_function(fetch_fn, 0) do
    case Base.get_value(:esi, key) do
      {:ok, nil} ->
        case fetch_fn.() do
          {:ok, data} ->
            Base.set_value(:esi, key, data)
            {:ok, data}

          {:error, _reason} = error ->
            error
        end

      {:ok, data} ->
        {:ok, data}

      error ->
        error
    end
  end

  def fetch_or_store(key, nil) do
    Base.get_value(:esi, key)
  end

  @doc """
  Handles common HTTP API response patterns for ESI endpoints.

  This function standardizes error handling across all ESI API calls,
  reducing boilerplate and ensuring consistent error responses.

  ## Options
  - `:params` - Query parameters (default: [])
  - `:timeout` - Request timeout in milliseconds (default: 30_000)
  - `:retries` - Number of retry attempts (default: 3)

  ## Returns
  - `{:ok, parsed_data}` - On successful response
  - `{:error, reason}` - On HTTP error or parsing failure

  ## Examples

  ```elixir
  parser = fn body ->
    %Types.CharacterInfo{
      character_id: char_id,
      name: Map.get(body, "name")
    }
  end

  handle_api_response(url, parser, params: [datasource: "tranquility"])
  ```
  """
  @spec handle_api_response(String.t(), (map() -> term()), keyword()) ::
          {:ok, term()} | {:error, term()}
  def handle_api_response(url, parser_fn, opts \\ []) when is_function(parser_fn, 1) do
    params = Keyword.get(opts, :params, [])
    timeout = Keyword.get(opts, :timeout, 30_000)

    case ClientProvider.get().get_with_rate_limit(url, params: params, timeout: timeout) do
      {:ok, %{body: body}} ->
        try do
          parsed_data = parser_fn.(body)
          {:ok, parsed_data}
        rescue
          error ->
            Logger.error("Failed to parse ESI response for #{url}: #{inspect(error)}")
            {:error, :parse_error}
        end

      {:error, reason} ->
        Logger.error("ESI API request failed for #{url}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Ensures data is cached for the specified entity type and ID.

  This is a convenience function that consolidates the common pattern of
  fetching data and only caring about whether it was successfully cached,
  not about retrieving the actual data.

  ## Parameters
  - `type` - The type of entity (:character, :corporation, :alliance, :type, :group, :system)
  - `id` - The ID of the entity
  - `opts` - Optional parameters (currently unused, reserved for future use)

  ## Returns
  - `:ok` - If data was successfully fetched/cached
  - `{:error, reason}` - If fetching failed

  ## Examples

     ```elixir
   case EsiCache.ensure_cached(:type, 588) do
     :ok -> Logger.info("Ship type 588 is now cached")
     {:error, error} -> Logger.error("Failed to cache ship type: \#{error}")
   end

  # Batch ensure caching
  Enum.each(type_ids, &EsiCache.ensure_cached(:type, &1))
  ```
  """
  @spec ensure_cached(atom(), pos_integer(), keyword()) :: :ok | {:error, term()}
  def ensure_cached(type, id, _opts \\ []) when is_atom(type) and is_integer(id) do
    case type do
      :character -> get_character_info(id) |> handle_ensure_result()
      :corporation -> get_corporation_info(id) |> handle_ensure_result()
      :alliance -> get_alliance_info(id) |> handle_ensure_result()
      :type -> get_type_info(id) |> handle_ensure_result()
      :group -> get_group_info(id) |> handle_ensure_result()
      :system -> get_system_info(id) |> handle_ensure_result()
      _ -> {:error, :invalid_type}
    end
  end

  # Helper to convert fetch results to ensure results
  defp handle_ensure_result({:ok, _data}), do: :ok
  defp handle_ensure_result({:error, reason}), do: {:error, reason}

  @doc """
  Gets character information from ESI API with caching.
  Returns {:ok, %Types.CharacterInfo{}} or {:error, reason}.
  """
  @spec get_character_info(character_id()) ::
          {:ok, Types.CharacterInfo.t()} | {:error, term()}
  def get_character_info(character_id) do
    parser_fn = fn body ->
      %Types.CharacterInfo{
        character_id: character_id,
        name: Map.get(body, "name"),
        corporation_id: Map.get(body, "corporation_id"),
        alliance_id: Map.get(body, "alliance_id"),
        faction_id: Map.get(body, "faction_id"),
        security_status: Map.get(body, "security_status")
      }
    end

    fetch_esi_info(&Key.character_info_key/1, "/characters", character_id, parser_fn)
  end

  @doc """
  Gets corporation information from ESI API with caching.
  Returns {:ok, %Types.CorporationInfo{}} or {:error, reason}.
  """
  @spec get_corporation_info(corporation_id()) ::
          {:ok, Types.CorporationInfo.t()} | {:error, term()}
  def get_corporation_info(corporation_id) do
    parser_fn = fn body ->
      %Types.CorporationInfo{
        corporation_id: corporation_id,
        name: Map.get(body, "name"),
        alliance_id: Map.get(body, "alliance_id"),
        faction_id: Map.get(body, "faction_id"),
        ticker: Map.get(body, "ticker"),
        member_count: Map.get(body, "member_count"),
        ceo_id: Map.get(body, "ceo_id")
      }
    end

    fetch_esi_info(&Key.corporation_info_key/1, "/corporations", corporation_id, parser_fn)
  end

  @doc """
  Gets alliance information from ESI API with caching.
  Returns {:ok, %Types.AllianceInfo{}} or {:error, reason}.
  """
  @spec get_alliance_info(alliance_id()) ::
          {:ok, Types.AllianceInfo.t()} | {:error, term()}
  def get_alliance_info(alliance_id) do
    parser_fn = fn body ->
      %Types.AllianceInfo{
        alliance_id: alliance_id,
        name: Map.get(body, "name"),
        ticker: Map.get(body, "ticker"),
        creator_corporation_id: Map.get(body, "creator_corporation_id"),
        creator_id: Map.get(body, "creator_id"),
        date_founded: Map.get(body, "date_founded"),
        executor_corporation_id: Map.get(body, "executor_corporation_id")
      }
    end

    fetch_esi_info(&Key.alliance_info_key/1, "/alliances", alliance_id, parser_fn)
  end

  @doc """
  Gets type information from ESI API with caching.
  Returns {:ok, %Types.TypeInfo{}} or {:error, reason}.
  """
  @spec get_type_info(type_id()) :: {:ok, Types.TypeInfo.t()} | {:error, term()}
  def get_type_info(type_id) do
    parser_fn = fn body ->
      %Types.TypeInfo{
        type_id: type_id,
        name: Map.get(body, "name"),
        description: Map.get(body, "description"),
        group_id: Map.get(body, "group_id"),
        market_group_id: Map.get(body, "market_group_id"),
        mass: Map.get(body, "mass"),
        packaged_volume: Map.get(body, "packaged_volume"),
        portion_size: Map.get(body, "portion_size"),
        published: Map.get(body, "published"),
        radius: Map.get(body, "radius"),
        volume: Map.get(body, "volume")
      }
    end

    fetch_esi_info(&Key.type_info_key/1, "/universe/types", type_id, parser_fn)
  end

  @doc """
  Gets group information from ESI API with caching.
  Returns {:ok, %Types.GroupInfo{}} or {:error, reason}.
  """
  @spec get_group_info(group_id()) :: {:ok, Types.GroupInfo.t()} | {:error, term()}
  def get_group_info(group_id) do
    parser_fn = fn body ->
      %Types.GroupInfo{
        group_id: group_id,
        name: Map.get(body, "name"),
        category_id: Map.get(body, "category_id"),
        published: Map.get(body, "published"),
        types: Map.get(body, "types", [])
      }
    end

    fetch_esi_info(&Key.group_info_key/1, "/universe/groups", group_id, parser_fn)
  end

  @doc """
  Gets solar system information from ESI API with caching.
  Returns {:ok, %Types.SystemInfo{}} or {:error, reason}.
  """
  @spec get_system_info(system_id()) :: {:ok, Types.SystemInfo.t()} | {:error, term()}
  def get_system_info(system_id) do
    parser_fn = fn body ->
      %Types.SystemInfo{
        system_id: system_id,
        name: Map.get(body, "name"),
        constellation_id: Map.get(body, "constellation_id"),
        security_status: Map.get(body, "security_status"),
        star_id: Map.get(body, "star_id")
      }
    end

    fetch_esi_info(&Key.system_info_key/1, "/universe/systems", system_id, parser_fn)
  end

  @doc """
  Gets all type IDs from the ESI API.
  """
  @spec get_all_types() :: {:ok, [integer()]} | {:error, term()}
  def get_all_types do
    key = Key.generate(:esi, ["types", "all"])
    url = "#{base_url()}/universe/types/"
    params = [datasource: "tranquility"]

    parser_fn = fn body ->
      if is_list(body) do
        body
      else
        raise "Expected list, got: #{inspect(body)}"
      end
    end

    fetch_fn = fn -> handle_api_response(url, parser_fn, params: params) end
    fetch_or_store(key, fetch_fn)
  end

  @doc """
  Fetches a killmail from the ESI API.
  Returns {:ok, killmail} or {:error, reason}.
  """
  @spec get_killmail(integer(), String.t()) :: {:ok, map()} | {:error, term()}
  def get_killmail(killmail_id, killmail_hash) do
    url = "#{base_url()}/killmails/#{killmail_id}/#{killmail_hash}/"

    case ClientProvider.get().get_with_rate_limit(url, []) do
      {:ok, %{body: body}} -> {:ok, body}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Clear all entries from the ESI cache.
  """
  def clear do
    Base.clear(:esi)
  end
end
