defmodule WandererKills.Http.ClientProvider do
  @moduledoc """
  Centralized HTTP client configuration and utilities provider.

  This module provides a single point for accessing HTTP client configuration,
  default headers, timeouts, and other HTTP-related utilities, eliminating
  the need for duplicate configurations across modules.

  ## Usage

  ```elixir
  alias WandererKills.Http.ClientProvider

  client = ClientProvider.get_client()
  headers = ClientProvider.default_headers()
  timeout = ClientProvider.default_timeout()
  ```
  """

  alias WandererKills.Infrastructure.Config

  @user_agent "(wanderer-kills@proton.me; +https://github.com/wanderer-industries/wanderer-kills)"

  @doc """
  Gets the configured HTTP client module.

  Returns the HTTP client configured in the application environment,
  defaulting to `WandererKills.Http.Client` if not specified.
  """
  @spec get_client() :: module()
  def get_client do
    Config.app().http_client
  end

  @doc """
  Gets default HTTP headers for API requests.

  ## Options
  - `:user_agent` - Custom user agent (defaults to application user agent)
  - `:accept` - Accept header (defaults to "application/json")
  - `:encoding` - Accept-Encoding header (defaults to "gzip")
  """
  @spec default_headers(keyword()) :: [{String.t(), String.t()}]
  def default_headers(opts \\ []) do
    user_agent = Keyword.get(opts, :user_agent, @user_agent)
    accept = Keyword.get(opts, :accept, "application/json")
    encoding = Keyword.get(opts, :encoding, "gzip")

    [
      {"User-Agent", user_agent},
      {"Accept", accept},
      {"Accept-Encoding", encoding}
    ]
  end

  @doc """
  Gets EVE Online API specific headers.
  """
  @spec eve_api_headers() :: [{String.t(), String.t()}]
  def eve_api_headers do
    default_headers()
  end

  @doc """
  Gets default request timeout from configuration.
  """
  @spec default_timeout() :: integer()
  def default_timeout do
    Config.timeouts().default_request_ms
  end

  @doc """
  Gets ESI-specific timeout from configuration.
  """
  @spec esi_timeout() :: integer()
  def esi_timeout do
    Config.timeouts().esi_request_ms
  end

  @doc """
  Builds standard request options with defaults.

  ## Options
  - `:timeout` - Request timeout (defaults to configured default)
  - `:headers` - Additional headers (merged with defaults)
  - `:params` - Query parameters
  """
  @spec build_request_opts(keyword()) :: keyword()
  def build_request_opts(opts \\ []) do
    timeout = Keyword.get(opts, :timeout, default_timeout())
    custom_headers = Keyword.get(opts, :headers, [])
    params = Keyword.get(opts, :params, [])

    headers = default_headers() ++ custom_headers

    [
      headers: headers,
      params: filter_params(params),
      timeout: timeout,
      recv_timeout: timeout
    ]
  end

  # Private functions

  @spec filter_params(keyword()) :: keyword()
  defp filter_params(params) do
    params
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Enum.map(fn
      {key, true} -> {key, "true"}
      {key, false} -> {key, "false"}
      {key, value} when is_integer(value) -> {key, Integer.to_string(value)}
      {key, value} -> {key, value}
    end)
  end
end
