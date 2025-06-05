defmodule WandererKills.Http.ClientProvider do
  @moduledoc """
  Centralized HTTP client configuration provider.

  This module provides a single point for accessing the configured HTTP client,
  eliminating the need for duplicate `http_client/0` functions across modules.

  ## Usage

  ```elixir
  alias WandererKills.Http.ClientProvider

  client = ClientProvider.get()
  case client.get_with_rate_limit(url, opts) do
    {:ok, response} -> ...
    {:error, reason} -> ...
  end
  ```
  """

  alias WandererKills.Http.Client

  @doc """
  Gets the configured HTTP client module.

  Returns the HTTP client configured in the application environment,
  defaulting to `WandererKills.Http.Client` if not specified.

  ## Returns
  The HTTP client module that implements the client behaviour.

  ## Examples

  ```elixir
  client = ClientProvider.get()
  # Returns WandererKills.Http.Client (default)
  # or WandererKills.Http.Client.Mock (in tests)
  ```
  """
  @spec get() :: module()
  def get do
    Application.get_env(:wanderer_kills, :http_client, Client)
  end
end
