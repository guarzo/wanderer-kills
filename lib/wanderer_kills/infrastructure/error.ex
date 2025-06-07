defmodule WandererKills.Infrastructure.Error do
  @moduledoc """
  Centralized error handling for WandererKills.

  This module provides a unified error structure and helper functions for all
  error handling across the application, replacing disparate error tuple patterns
  with a consistent approach.

  ## Error Structure

  All errors have a standardized format with:
  - `domain` - Which part of the system generated the error
  - `type` - Specific error type within the domain
  - `message` - Human-readable error message
  - `details` - Additional error context (optional)
  - `retryable` - Whether the operation can be retried

  ## Usage

  ```elixir
  # HTTP errors
  {:error, Error.http_error(:timeout, "Request timed out", true)}

  # Cache errors
  {:error, Error.cache_error(:miss, "Cache key not found")}

  # Killmail processing errors
  {:error, Error.killmail_error(:invalid_format, "Missing required fields")}

  # Checking if error is retryable
  if Error.retryable?(error) do
    retry_operation()
  end

  # Creating standardized errors
  Error.not_found_error("Resource not found")
  ```
  """

  defstruct [:domain, :type, :message, :details, :retryable]

  @type domain ::
          :http
          | :cache
          | :killmail
          | :system
          | :esi
          | :zkb
          | :parsing
          | :enrichment
          | :redis_q
          | :ship_types
          | :validation
          | :config
          | :time
          | :csv
  @type error_type :: atom()
  @type details :: map() | nil

  @type t :: %__MODULE__{
          domain: domain(),
          type: error_type(),
          message: String.t(),
          details: details(),
          retryable: boolean()
        }

  # ============================================================================
  # Constructor Functions by Domain
  # ============================================================================

  @doc "Creates an HTTP-related error"
  @spec http_error(error_type(), String.t(), boolean(), details()) :: t()
  def http_error(type, message, retryable \\ false, details \\ nil) do
    %__MODULE__{
      domain: :http,
      type: type,
      message: message,
      details: details,
      retryable: retryable
    }
  end

  @doc "Creates a cache-related error"
  @spec cache_error(error_type(), String.t(), details()) :: t()
  def cache_error(type, message, details \\ nil) do
    %__MODULE__{
      domain: :cache,
      type: type,
      message: message,
      details: details,
      retryable: false
    }
  end

  @doc "Creates a killmail processing error"
  @spec killmail_error(error_type(), String.t(), boolean(), details()) :: t()
  def killmail_error(type, message, retryable \\ false, details \\ nil) do
    %__MODULE__{
      domain: :killmail,
      type: type,
      message: message,
      details: details,
      retryable: retryable
    }
  end

  @doc "Creates a system-related error"
  @spec system_error(error_type(), String.t(), boolean(), details()) :: t()
  def system_error(type, message, retryable \\ false, details \\ nil) do
    %__MODULE__{
      domain: :system,
      type: type,
      message: message,
      details: details,
      retryable: retryable
    }
  end

  @doc "Creates an ESI API error"
  @spec esi_error(error_type(), String.t(), boolean(), details()) :: t()
  def esi_error(type, message, retryable \\ false, details \\ nil) do
    %__MODULE__{
      domain: :esi,
      type: type,
      message: message,
      details: details,
      retryable: retryable
    }
  end

  @doc "Creates a zKillboard API error"
  @spec zkb_error(error_type(), String.t(), boolean(), details()) :: t()
  def zkb_error(type, message, retryable \\ false, details \\ nil) do
    %__MODULE__{
      domain: :zkb,
      type: type,
      message: message,
      details: details,
      retryable: retryable
    }
  end

  @doc "Creates a parsing error"
  @spec parsing_error(error_type(), String.t(), details()) :: t()
  def parsing_error(type, message, details \\ nil) do
    %__MODULE__{
      domain: :parsing,
      type: type,
      message: message,
      details: details,
      retryable: false
    }
  end

  @doc "Creates an enrichment error"
  @spec enrichment_error(error_type(), String.t(), boolean(), details()) :: t()
  def enrichment_error(type, message, retryable \\ false, details \\ nil) do
    %__MODULE__{
      domain: :enrichment,
      type: type,
      message: message,
      details: details,
      retryable: retryable
    }
  end

  @doc "Creates a RedisQ error"
  @spec redisq_error(error_type(), String.t(), boolean(), details()) :: t()
  def redisq_error(type, message, retryable \\ true, details \\ nil) do
    %__MODULE__{
      domain: :redis_q,
      type: type,
      message: message,
      details: details,
      retryable: retryable
    }
  end

  @doc "Creates a ship types error"
  @spec ship_types_error(error_type(), String.t(), boolean(), details()) :: t()
  def ship_types_error(type, message, retryable \\ false, details \\ nil) do
    %__MODULE__{
      domain: :ship_types,
      type: type,
      message: message,
      details: details,
      retryable: retryable
    }
  end

  @doc "Creates a validation error"
  @spec validation_error(error_type(), String.t(), details()) :: t()
  def validation_error(type, message, details \\ nil) do
    %__MODULE__{
      domain: :validation,
      type: type,
      message: message,
      details: details,
      retryable: false
    }
  end

  @doc "Creates a configuration error"
  @spec config_error(error_type(), String.t(), details()) :: t()
  def config_error(type, message, details \\ nil) do
    %__MODULE__{
      domain: :config,
      type: type,
      message: message,
      details: details,
      retryable: false
    }
  end

  @doc "Creates a time processing error"
  @spec time_error(error_type(), String.t(), details()) :: t()
  def time_error(type, message, details \\ nil) do
    %__MODULE__{
      domain: :time,
      type: type,
      message: message,
      details: details,
      retryable: false
    }
  end

  @doc "Creates a CSV processing error"
  @spec csv_error(error_type(), String.t(), details()) :: t()
  def csv_error(type, message, details \\ nil) do
    %__MODULE__{
      domain: :csv,
      type: type,
      message: message,
      details: details,
      retryable: false
    }
  end

  # ============================================================================
  # Utility Functions
  # ============================================================================

  @doc "Checks if an error is retryable"
  @spec retryable?(t()) :: boolean()
  def retryable?(%__MODULE__{retryable: retryable}), do: retryable

  @doc "Gets the error domain"
  @spec domain(t()) :: domain()
  def domain(%__MODULE__{domain: domain}), do: domain

  @doc "Gets the error type"
  @spec type(t()) :: error_type()
  def type(%__MODULE__{type: type}), do: type

  @doc "Gets the error message"
  @spec message(t()) :: String.t()
  def message(%__MODULE__{message: message}), do: message

  @doc "Gets the error details"
  @spec details(t()) :: details()
  def details(%__MODULE__{details: details}), do: details

  @doc "Converts an error to a string representation"
  @spec to_string(t()) :: String.t()
  def to_string(%__MODULE__{domain: domain, type: type, message: message}) do
    "[#{domain}:#{type}] #{message}"
  end

  @doc "Converts an error to a map for serialization"
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = error) do
    %{
      domain: error.domain,
      type: error.type,
      message: error.message,
      details: error.details,
      retryable: error.retryable
    }
  end

  # ============================================================================
  # Common Error Patterns
  # ============================================================================

  @doc "Standard timeout error"
  @spec timeout_error(String.t(), details()) :: t()
  def timeout_error(message \\ "Operation timed out", details \\ nil) do
    http_error(:timeout, message, true, details)
  end

  @doc "Standard not found error"
  @spec not_found_error(String.t(), details()) :: t()
  def not_found_error(message \\ "Resource not found", details \\ nil) do
    system_error(:not_found, message, false, details)
  end

  @doc "Standard invalid format error"
  @spec invalid_format_error(String.t(), details()) :: t()
  def invalid_format_error(message \\ "Invalid data format", details \\ nil) do
    validation_error(:invalid_format, message, details)
  end

  @doc "Standard rate limit error"
  @spec rate_limit_error(String.t(), details()) :: t()
  def rate_limit_error(message \\ "Rate limit exceeded", details \\ nil) do
    http_error(:rate_limited, message, true, details)
  end

  @doc "Standard connection error"
  @spec connection_error(String.t(), details()) :: t()
  def connection_error(message \\ "Connection failed", details \\ nil) do
    http_error(:connection_failed, message, true, details)
  end

  # ============================================================================
  # HTTP Exception Types
  # ============================================================================

  defmodule ConnectionError do
    @moduledoc """
    Error raised when a connection fails.
    """
    defexception [:message]
  end

  defmodule TimeoutError do
    @moduledoc """
    Error raised when a request times out.
    """
    defexception [:message]
  end

  defmodule RateLimitError do
    @moduledoc """
    Error raised when rate limit is exceeded.
    """
    defexception [:message]
  end
end
