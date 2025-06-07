defmodule WandererKills.Core.Cache.Errors do
  @moduledoc """
  Standardized error types for cache operations.
  """

  @type cache_error :: {:error, {:cache, reason()}}
  @type http_error :: {:error, {:http, reason()}}
  @type reason :: atom() | String.t() | integer() | map()

  @doc """
  Creates a standardized cache error tuple.
  """
  @spec cache_error(reason()) :: cache_error()
  def cache_error(reason) when is_integer(reason), do: {:error, {:cache, to_string(reason)}}
  def cache_error(reason), do: {:error, {:cache, reason}}

  @doc """
  Creates a standardized HTTP error tuple.
  """
  @spec http_error(reason()) :: http_error()
  def http_error(reason), do: {:error, {:http, reason}}

  @doc """
  Checks if an error tuple is a cache error.
  """
  @spec cache_error?(term()) :: boolean()
  def cache_error?({:error, {:cache, _}}), do: true
  def cache_error?(_), do: false

  @doc """
  Checks if an error tuple is an HTTP error.
  """
  @spec http_error?(term()) :: boolean()
  def http_error?({:error, {:http, _}}), do: true
  def http_error?(_), do: false
end
