defmodule WandererKills.Core do
  @moduledoc """
  Compatibility module for legacy Core module references.

  This module provides aliases for modules that have been moved to domain-specific
  directories as part of the codebase restructuring. These aliases maintain
  backward compatibility while the codebase is gradually updated.

  ## Migration Guide

  Old modules have been moved to domain-specific locations:

  ### HTTP Modules
  - `WandererKills.Core.Http.Client` → `WandererKills.Http.Client`
  - `WandererKills.Core.Http.ClientProvider` → `WandererKills.Http.ClientProvider`
  - `WandererKills.Core.Http.Util` → `WandererKills.Http.Util`

  ### Processing Modules
  - `WandererKills.Core.BatchProcessor` → `WandererKills.Processing.BatchProcessor`
  - `WandererKills.Core.CSV` → `WandererKills.Processing.CSV`

  ### Cache Modules
  - `WandererKills.Core.CacheUtils` → `WandererKills.Cache.Utils`

  ### Infrastructure Modules
  - `WandererKills.Core.Config` → `WandererKills.Infrastructure.Config`
  - `WandererKills.Core.Retry` → `WandererKills.Infrastructure.Retry`
  - `WandererKills.Core.Clock` → `WandererKills.Infrastructure.Clock`
  - `WandererKills.Core.Constants` → `WandererKills.Infrastructure.Constants`
  - `WandererKills.Core.Behaviours` → `WandererKills.Infrastructure.Behaviours`
  - `WandererKills.Core.Error` → `WandererKills.Infrastructure.Error`
  """

  # HTTP Module Aliases
  defmodule Http do
    defmodule Client do
      @moduledoc false
      defdelegate get(url, headers \\ [], options \\ []), to: WandererKills.Http.Client
      defdelegate get_with_rate_limit(url, opts \\ []), to: WandererKills.Http.Client
      defdelegate handle_status_code(status, resp \\ %{}), to: WandererKills.Http.Client
      defdelegate retriable_error?(error), to: WandererKills.Http.Client
    end

    defmodule ClientProvider do
      @moduledoc false
      defdelegate get(), to: WandererKills.Http.ClientProvider
    end

    defmodule Util do
      @moduledoc false
      defdelegate request_with_telemetry(url, service, opts \\ []), to: WandererKills.Http.Util
      defdelegate parse_json_response(response), to: WandererKills.Http.Util
      defdelegate build_query_params(params), to: WandererKills.Http.Util
      defdelegate eve_api_headers(user_agent \\ nil), to: WandererKills.Http.Util
      defdelegate retry_operation(fun, service, opts \\ []), to: WandererKills.Http.Util
      defdelegate validate_response_structure(data, required_fields), to: WandererKills.Http.Util
    end
  end

  # Processing Module Aliases
  defmodule BatchProcessor do
    @moduledoc false
    defdelegate process_parallel(items, process_fn, opts \\ []),
      to: WandererKills.Processing.BatchProcessor

    defdelegate await_tasks(tasks, opts \\ []), to: WandererKills.Processing.BatchProcessor
  end

  defmodule CSV do
    @moduledoc false
    defdelegate parse_ship_type_csvs(file_paths), to: WandererKills.Processing.CSV
    defdelegate download_csv_files(opts \\ []), to: WandererKills.Processing.CSV
    defdelegate read_file(file_path, parser, opts \\ []), to: WandererKills.Processing.CSV

    def parse_ship_types_csv(csv_content), do: parse_ship_type_csvs([csv_content])
    def download_ship_types_csv(), do: download_csv_files()

    def get_ship_types_from_csv(),
      do: read_file("ship_types.csv", &WandererKills.Processing.CSV.parse_type_row/1)

    def update_ship_types(), do: parse_ship_type_csvs(["invTypes.csv", "invGroups.csv"])
  end

  # Cache Module Aliases
  defmodule CacheUtils do
    @moduledoc false
    defdelegate cache_killmails_for_system(system_id, killmails), to: WandererKills.Cache.Utils
  end

  # Infrastructure Module Aliases
  defmodule Config do
    @moduledoc false
    defdelegate config(), to: WandererKills.Infrastructure.Config
    defdelegate cache(), to: WandererKills.Infrastructure.Config
    defdelegate retry(), to: WandererKills.Infrastructure.Config
    defdelegate batch(), to: WandererKills.Infrastructure.Config
    defdelegate timeouts(), to: WandererKills.Infrastructure.Config
    defdelegate http_status(), to: WandererKills.Infrastructure.Config
    defdelegate services(), to: WandererKills.Infrastructure.Config
    defdelegate redisq(), to: WandererKills.Infrastructure.Config
    defdelegate parser(), to: WandererKills.Infrastructure.Config
    defdelegate enricher(), to: WandererKills.Infrastructure.Config
    defdelegate killmail_store(), to: WandererKills.Infrastructure.Config
    defdelegate telemetry(), to: WandererKills.Infrastructure.Config
    defdelegate app(), to: WandererKills.Infrastructure.Config

    def start_preloader?(), do: Application.get_env(:wanderer_kills, :start_preloader, false)
    def cache_killmails_name(), do: :wanderer_kills_cache
    def cache_system_name(), do: :wanderer_kills_system_cache
    def cache_esi_name(), do: :wanderer_kills_esi_cache
  end

  defmodule Retry do
    @moduledoc false
    defdelegate retry_with_backoff(fun, opts \\ []), to: WandererKills.Infrastructure.Retry
    defdelegate retriable_http_error?(reason), to: WandererKills.Infrastructure.Retry
    defdelegate retriable_error?(reason), to: WandererKills.Infrastructure.Retry
    defdelegate retry_http_operation(fun, opts \\ []), to: WandererKills.Infrastructure.Retry
  end

  defmodule Clock do
    @moduledoc false
    defdelegate now(), to: WandererKills.Infrastructure.Clock
    defdelegate system_time(), to: WandererKills.Infrastructure.Clock
    defdelegate system_time(unit), to: WandererKills.Infrastructure.Clock
    defdelegate now_iso8601(), to: WandererKills.Infrastructure.Clock
    defdelegate now_milliseconds(), to: WandererKills.Infrastructure.Clock
    defdelegate hours_ago(hours), to: WandererKills.Infrastructure.Clock
    defdelegate seconds_ago(seconds), to: WandererKills.Infrastructure.Clock

    def utc_now(), do: WandererKills.Infrastructure.Clock.now()

    def get_system_time_with_config(unit),
      do: WandererKills.Infrastructure.Clock.system_time(unit)
  end

  defmodule Constants do
    @moduledoc false
    defdelegate gen_server_call_timeout(), to: WandererKills.Infrastructure.Constants
    defdelegate retry_base_delay(), to: WandererKills.Infrastructure.Constants
    defdelegate retry_max_delay(), to: WandererKills.Infrastructure.Constants
    defdelegate retry_backoff_factor(), to: WandererKills.Infrastructure.Constants
    defdelegate validation(type), to: WandererKills.Infrastructure.Constants
  end

  defmodule Behaviours do
    @moduledoc false
    # Re-export the behaviour modules for backward compatibility

    defmodule HttpClient do
      @moduledoc false
      defdelegate get(url, headers, options), to: WandererKills.Http.Client
      defdelegate get_with_rate_limit(url, opts), to: WandererKills.Http.Client
    end

    defmodule DataFetcher do
      @moduledoc false
      # Legacy DataFetcher behavior - these need to be implemented by actual clients
      @callback fetch(term()) :: {:ok, term()} | {:error, term()}
      @callback fetch_many([term()]) :: {:ok, [term()]} | {:error, term()}
      @callback supports?(term()) :: boolean()
    end

    defmodule ESIClient do
      @moduledoc false
      # Legacy ESIClient behavior - define callbacks for backward compatibility
      @callback get_alliance(integer()) :: {:ok, map()} | {:error, term()}
      @callback get_alliance_batch([integer()]) :: {:ok, [map()]} | {:error, term()}
      @callback get_character(integer()) :: {:ok, map()} | {:error, term()}
      @callback get_character_batch([integer()]) :: {:ok, [map()]} | {:error, term()}
      @callback get_corporation(integer()) :: {:ok, map()} | {:error, term()}
      @callback get_corporation_batch([integer()]) :: {:ok, [map()]} | {:error, term()}
      @callback get_group(integer()) :: {:ok, map()} | {:error, term()}
      @callback get_group_batch([integer()]) :: {:ok, [map()]} | {:error, term()}
      @callback get_system(integer()) :: {:ok, map()} | {:error, term()}
      @callback get_system_batch([integer()]) :: {:ok, [map()]} | {:error, term()}
      @callback get_type(integer()) :: {:ok, map()} | {:error, term()}
      @callback get_type_batch([integer()]) :: {:ok, [map()]} | {:error, term()}

      # Default implementation delegates to ESI client
      defdelegate get_alliance(id), to: WandererKills.ESI.Client
      defdelegate get_alliance_batch(ids), to: WandererKills.ESI.Client
      defdelegate get_character(id), to: WandererKills.ESI.Client
      defdelegate get_character_batch(ids), to: WandererKills.ESI.Client
      defdelegate get_corporation(id), to: WandererKills.ESI.Client
      defdelegate get_corporation_batch(ids), to: WandererKills.ESI.Client
      defdelegate get_group(id), to: WandererKills.ESI.Client
      defdelegate get_group_batch(ids), to: WandererKills.ESI.Client
      defdelegate get_system(id), to: WandererKills.ESI.Client
      defdelegate get_system_batch(ids), to: WandererKills.ESI.Client
      defdelegate get_type(id), to: WandererKills.ESI.Client
      defdelegate get_type_batch(ids), to: WandererKills.ESI.Client
    end
  end

  defmodule Error do
    @moduledoc false
    defdelegate esi_error(type, message, retryable \\ false, details \\ nil),
      to: WandererKills.Infrastructure.Error

    defdelegate zkb_error(type, message, retryable \\ false, details \\ nil),
      to: WandererKills.Infrastructure.Error

    defdelegate http_error(type, message, retryable \\ false, details \\ nil),
      to: WandererKills.Infrastructure.Error

    defdelegate validation_error(type, message, details \\ nil),
      to: WandererKills.Infrastructure.Error

    defdelegate parsing_error(type, message, details \\ nil),
      to: WandererKills.Infrastructure.Error

    defdelegate cache_error(type, message, details \\ nil),
      to: WandererKills.Infrastructure.Error

    defdelegate killmail_error(type, message, retryable \\ false, details \\ nil),
      to: WandererKills.Infrastructure.Error

    defdelegate enrichment_error(type, message, retryable \\ false, details \\ nil),
      to: WandererKills.Infrastructure.Error

    defdelegate ship_types_error(type, message, retryable \\ false, details \\ nil),
      to: WandererKills.Infrastructure.Error

    defdelegate not_found_error(message, details \\ nil),
      to: WandererKills.Infrastructure.Error
  end
end
