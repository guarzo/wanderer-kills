defmodule WandererKills do
  @moduledoc """
  WandererKills is a standalone service for retrieving and caching EVE Online killmails from zKillboard.

  ## Features

  * Fetches killmails from zKillboard API
  * Caches killmails and related data
  * Provides HTTP API endpoints for accessing killmail data
  * Supports system-specific killmail queries
  * Includes ship type information enrichment
  """

  @doc """
  Returns the application version.
  """
  def version do
    case Application.spec(:wanderer_kills) do
      nil -> "0.1.0"
      spec -> to_string(spec[:vsn])
    end
  end

  @doc """
  Returns the application name.
  """
  def app_name do
    case Application.spec(:wanderer_kills) do
      nil -> :wanderer_kills
      spec -> spec[:app] || :wanderer_kills
    end
  end
end
