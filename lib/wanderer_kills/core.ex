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
  - `WandererKills.Core.Http.Util` → **REMOVED** (functionality moved to `WandererKills.Http.Client`)

  ### Processing Modules
  - `WandererKills.Core.BatchProcessor` → `WandererKills.Support.BatchProcessor`
  - `WandererKills.Core.CSV` → `WandererKills.ShipTypes.CSV`

  ### Cache Modules
  - `WandererKills.Core.CacheUtils` → `WandererKills.Cache.Utils`

  ### Infrastructure Modules
  - `WandererKills.Core.Config` → `WandererKills.Config`
  - `WandererKills.Core.Retry` → `WandererKills.Support.Retry`
  - `WandererKills.Core.Clock` → `WandererKills.Support.Clock`
  - `WandererKills.Core.Constants` → `WandererKills.Config`
  - `WandererKills.Core.Behaviours` → `WandererKills.Support.Behaviours`
  - `WandererKills.Core.Error` → `WandererKills.Support.Error`
  """

  # HTTP Module Aliases (consolidated)
  defmodule Http do
    @moduledoc """
    Legacy HTTP module aliases for backward compatibility.

    Provides aliases to new HTTP modules in the WandererKills.Http namespace.
    This module maintains backward compatibility while the codebase transitions
    to the new module structure.
    """

    defmodule Client do
      @moduledoc false
      # Core HTTP client functions
      defdelegate get(url, headers \\ [], options \\ []), to: WandererKills.Http.Client
      defdelegate get_with_rate_limit(url, opts \\ []), to: WandererKills.Http.Client
      defdelegate handle_status_code(status, resp \\ %{}), to: WandererKills.Http.Client
      defdelegate retriable_error?(error), to: WandererKills.Http.Client

      # Consolidated utility functions (moved from Http.Util)
      defdelegate request_with_telemetry(url, service, opts \\ []), to: WandererKills.Http.Client
      defdelegate parse_json_response(response), to: WandererKills.Http.Client
      defdelegate retry_operation(fun, service, opts \\ []), to: WandererKills.Http.Client

      defdelegate validate_response_structure(data, required_fields),
        to: WandererKills.Http.Client
    end

    defmodule ClientProvider do
      @moduledoc false
      # Enhanced configuration provider
      defdelegate get_client(), to: WandererKills.Http.ClientProvider
      defdelegate default_headers(opts \\ []), to: WandererKills.Http.ClientProvider
      defdelegate eve_api_headers(), to: WandererKills.Http.ClientProvider
      defdelegate default_timeout(), to: WandererKills.Http.ClientProvider
      defdelegate esi_timeout(), to: WandererKills.Http.ClientProvider
      defdelegate build_request_opts(opts \\ []), to: WandererKills.Http.ClientProvider

      # Legacy compatibility
      def get, do: get_client()
    end
  end

  # Processing Module Aliases
  defmodule BatchProcessor do
    @moduledoc false
    defdelegate process_parallel(items, process_fn, opts \\ []),
      to: WandererKills.Support.BatchProcessor

    defdelegate await_tasks(tasks, opts \\ []), to: WandererKills.Support.BatchProcessor
  end

  defmodule CSV do
    @moduledoc false
    defdelegate parse_ship_type_csvs(file_paths), to: WandererKills.ShipTypes.CSV
    defdelegate download_csv_files(opts \\ []), to: WandererKills.ShipTypes.CSV
    defdelegate read_file(file_path, parser, opts \\ []), to: WandererKills.ShipTypes.CSV
  end

  # Infrastructure Module Aliases
  defmodule Config do
    @moduledoc false
    defdelegate config(), to: WandererKills.Config
    defdelegate cache(), to: WandererKills.Config
    defdelegate retry(), to: WandererKills.Config
    defdelegate batch(), to: WandererKills.Config
    defdelegate timeouts(), to: WandererKills.Config
    defdelegate http_status(), to: WandererKills.Config
    defdelegate services(), to: WandererKills.Config
    defdelegate redisq(), to: WandererKills.Config
    defdelegate parser(), to: WandererKills.Config
    defdelegate enricher(), to: WandererKills.Config
    defdelegate killmail_store(), to: WandererKills.Config
    defdelegate telemetry(), to: WandererKills.Config
    defdelegate app(), to: WandererKills.Config

    def start_preloader?, do: WandererKills.Config.start_preloader?()
  end

  defmodule Retry do
    @moduledoc false
    defdelegate retry_with_backoff(fun, opts \\ []), to: WandererKills.Support.Retry
    defdelegate retriable_http_error?(reason), to: WandererKills.Support.Retry
    defdelegate retriable_error?(reason), to: WandererKills.Support.Retry
    defdelegate retry_http_operation(fun, opts \\ []), to: WandererKills.Support.Retry
  end

  defmodule Clock do
    @moduledoc false
    defdelegate now(), to: WandererKills.Support.Clock
    defdelegate now_iso8601(), to: WandererKills.Support.Clock
    defdelegate now_milliseconds(), to: WandererKills.Support.Clock
    defdelegate hours_ago(hours), to: WandererKills.Support.Clock
    defdelegate seconds_ago(seconds), to: WandererKills.Support.Clock
  end

  defmodule Constants do
    @moduledoc false
    defdelegate gen_server_call_timeout(), to: WandererKills.Config
    defdelegate retry_base_delay(), to: WandererKills.Config
    defdelegate retry_max_delay(), to: WandererKills.Config
    defdelegate retry_backoff_factor(), to: WandererKills.Config
    defdelegate validation(type), to: WandererKills.Config
  end

  defmodule Error do
    @moduledoc false
    defdelegate esi_error(type, message, retryable \\ false, details \\ nil),
      to: WandererKills.Support.Error

    defdelegate zkb_error(type, message, retryable \\ false, details \\ nil),
      to: WandererKills.Support.Error

    defdelegate http_error(type, message, retryable \\ false, details \\ nil),
      to: WandererKills.Support.Error

    defdelegate validation_error(type, message, details \\ nil),
      to: WandererKills.Support.Error

    defdelegate parsing_error(type, message, details \\ nil),
      to: WandererKills.Support.Error

    defdelegate cache_error(type, message, details \\ nil),
      to: WandererKills.Support.Error

    defdelegate killmail_error(type, message, retryable \\ false, details \\ nil),
      to: WandererKills.Support.Error

    defdelegate enrichment_error(type, message, retryable \\ false, details \\ nil),
      to: WandererKills.Support.Error

    defdelegate ship_types_error(type, message, retryable \\ false, details \\ nil),
      to: WandererKills.Support.Error

    defdelegate not_found_error(message, details \\ nil),
      to: WandererKills.Support.Error
  end
end
