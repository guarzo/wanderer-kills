defmodule WandererKills.Parser.KillmailCache do
  @moduledoc """
  Cache operations for parsed killmail data.

  This module provides a focused API for killmail caching operations while
  following the consistent "Killmail" naming convention. It handles the storage
  and retrieval of processed killmail data.

  ## Features

  - Killmail storage in cache
  - Batch storage operations
  - Cache key management
  - Error handling and logging

  ## Usage

  ```elixir
  # Store a single killmail
  :ok = KillmailCache.store_killmail(killmail)

  # Store multiple killmails
  :ok = KillmailCache.store_killmails(killmails)

  # Retrieve a killmail
  {:ok, killmail} = KillmailCache.get_killmail(killmail_id)
  ```
  """

  require Logger
  alias WandererKills.Cache.Unified

  @type killmail :: map()
  @type killmail_id :: integer()

  @doc """
  Stores a processed killmail in the cache.

  ## Parameters
  - `killmail` - The processed killmail data to store

  ## Returns
  - `:ok` - On successful storage
  - `{:error, reason}` - On failure

  ## Examples

  ```elixir
  killmail = %{
    "killmail_id" => 12345,
    "kill_time" => ~U[2023-01-01 00:00:00Z],
    "solar_system_id" => 30000142,
    # ... other killmail data
  }

  case KillmailCache.store_killmail(killmail) do
    :ok -> Logger.info("Killmail stored successfully")
    {:error, _reason} -> Logger.error("Failed to store killmail")
  end
  ```
  """
  @spec store_killmail(killmail()) :: :ok | {:error, term()}
  def store_killmail(%{"killmail_id" => killmail_id} = killmail) when is_integer(killmail_id) do
    Logger.debug("Storing killmail in cache", killmail_id: killmail_id)

    try do
      case Unified.set_killmail(killmail_id, killmail) do
        {:ok, _} ->
          Logger.debug("Successfully stored killmail", killmail_id: killmail_id)
          :ok

        error ->
          Logger.error("Failed to store killmail",
            killmail_id: killmail_id,
            error: inspect(error)
          )

          error
      end
    rescue
      error ->
        Logger.error("Exception while storing killmail",
          killmail_id: killmail_id,
          error: inspect(error)
        )

        {:error, :storage_exception}
    end
  end

  def store_killmail(_), do: {:error, :invalid_killmail_format}

  @doc """
  Stores multiple killmails in batch.

  ## Parameters
  - `killmails` - List of processed killmail data to store

  ## Returns
  - `:ok` - If all killmails stored successfully
  - `{:error, failed_ids}` - If some killmails failed to store

  ## Examples

  ```elixir
  killmails = [killmail1, killmail2, killmail3]

  case KillmailCache.store_killmails(killmails) do
    :ok -> Logger.info("All killmails stored")
    {:error, _failed_ids} -> Logger.error("Failed to store some killmails")
  end
  ```
  """
  @spec store_killmails([killmail()]) :: :ok | {:error, [killmail_id()]}
  def store_killmails(killmails) when is_list(killmails) do
    Logger.debug("Storing batch of killmails", count: length(killmails))

    results =
      Enum.map(killmails, fn killmail ->
        case store_killmail(killmail) do
          :ok -> {:ok, get_killmail_id(killmail)}
          {:error, reason} -> {:error, {get_killmail_id(killmail), reason}}
        end
      end)

    {successful, failed} = Enum.split_with(results, &match?({:ok, _}, &1))

    case failed do
      [] ->
        Logger.info("Successfully stored all killmails", count: length(successful))
        :ok

      errors ->
        failed_ids = Enum.map(errors, fn {:error, {id, _reason}} -> id end)

        Logger.error("Failed to store some killmails",
          failed_count: length(errors),
          failed_ids: failed_ids
        )

        {:error, failed_ids}
    end
  end

  def store_killmails(_), do: {:error, :invalid_killmails_format}

  @doc """
  Retrieves a killmail from the cache.

  ## Parameters
  - `killmail_id` - The ID of the killmail to retrieve

  ## Returns
  - `{:ok, killmail}` - On successful retrieval
  - `{:error, reason}` - On failure

  ## Examples

  ```elixir
  case KillmailCache.get_killmail(12345) do
    {:ok, killmail} -> process_killmail(killmail)
    {:error, :not_found} -> Logger.info("Killmail not in cache")
  end
  ```
  """
  @spec get_killmail(killmail_id()) :: {:ok, killmail()} | {:error, term()}
  def get_killmail(killmail_id) when is_integer(killmail_id) do
    Logger.debug("Retrieving killmail from cache", killmail_id: killmail_id)

    case Unified.get_killmail(killmail_id) do
      {:ok, killmail} ->
        Logger.debug("Successfully retrieved killmail", killmail_id: killmail_id)
        {:ok, killmail}

      {:error, reason} ->
        Logger.debug("Failed to retrieve killmail",
          killmail_id: killmail_id,
          error: reason
        )

        {:error, reason}
    end
  end

  def get_killmail(_), do: {:error, :invalid_killmail_id}

  @doc """
  Checks if a killmail exists in the cache.

  ## Parameters
  - `killmail_id` - The ID of the killmail to check

  ## Returns
  - `true` - If killmail exists in cache
  - `false` - If killmail not in cache
  """
  @spec killmail_exists?(killmail_id()) :: boolean()
  def killmail_exists?(killmail_id) when is_integer(killmail_id) do
    case get_killmail(killmail_id) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  def killmail_exists?(_), do: false

  @doc """
  Removes a killmail from the cache.

  ## Parameters
  - `killmail_id` - The ID of the killmail to remove

  ## Returns
  - `:ok` - On successful removal
  - `{:error, reason}` - On failure
  """
  @spec remove_killmail(killmail_id()) :: :ok | {:error, term()}
  def remove_killmail(killmail_id) when is_integer(killmail_id) do
    Logger.debug("Removing killmail from cache", killmail_id: killmail_id)

    case Unified.delete_killmail(killmail_id) do
      {:ok, _} ->
        Logger.debug("Successfully removed killmail", killmail_id: killmail_id)
        :ok

      error ->
        Logger.error("Failed to remove killmail", killmail_id: killmail_id, error: inspect(error))
        error
    end
  end

  def remove_killmail(_), do: {:error, :invalid_killmail_id}

  # Private helper functions

  @spec get_killmail_id(killmail()) :: killmail_id() | nil
  defp get_killmail_id(%{"killmail_id" => id}) when is_integer(id), do: id
  defp get_killmail_id(_), do: nil
end
