defmodule WandererKills.Cache.SystemCache do
  @moduledoc """
  System-specific cache operations for WandererKills.
  """

  require Logger
  alias WandererKills.Cache.Helper

  @doc """
  Get killmails for a specific system.
  """
  def get_killmails(system_id) do
    case Helper.get("systems", "killmails:#{system_id}") do
      {:ok, nil} ->
        {:error, :not_found}

      {:ok, killmail_ids} when is_list(killmail_ids) ->
        {:ok, killmail_ids}

      {:ok, _invalid_data} ->
        # Clean up corrupted data
        Helper.delete("systems", "killmails:#{system_id}")
        {:error, :invalid_data}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Put killmails for a specific system.
  """
  def put_killmails(system_id, killmail_ids) when is_list(killmail_ids) do
    Helper.put("systems", "killmails:#{system_id}", killmail_ids)
  end

  @doc """
  Add a killmail to a system's killmail list.
  """
  def add_killmail(system_id, killmail_id) do
    case get_killmails(system_id) do
      {:ok, existing_ids} ->
        if killmail_id in existing_ids do
          {:ok, true}
        else
          new_ids = [killmail_id | existing_ids]
          put_killmails(system_id, new_ids)
        end

      {:error, :not_found} ->
        put_killmails(system_id, [killmail_id])

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Check if a system is active.
  """
  def active?(system_id) do
    case Helper.get("systems", "active:#{system_id}") do
      {:ok, nil} -> {:ok, false}
      {:ok, _timestamp} -> {:ok, true}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Add a system to the active systems list.
  """
  def add_active(system_id) do
    case active?(system_id) do
      {:ok, true} ->
        {:ok, :already_exists}

      {:ok, false} ->
        timestamp = DateTime.utc_now()

        case Helper.put("systems", "active:#{system_id}", timestamp) do
          {:ok, true} -> {:ok, :added}
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get the last fetch timestamp for a system.
  """
  def get_fetch_timestamp(system_id) do
    case Helper.get("systems", "fetch_timestamp:#{system_id}") do
      {:ok, nil} ->
        {:error, :not_found}

      {:ok, timestamp} when is_struct(timestamp, DateTime) ->
        {:ok, timestamp}

      {:ok, _invalid_data} ->
        # Clean up corrupted data
        Helper.delete("systems", "fetch_timestamp:#{system_id}")
        {:error, :invalid_data}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Set the fetch timestamp for a system.
  """
  def set_fetch_timestamp(system_id, timestamp \\ nil) do
    timestamp = timestamp || DateTime.utc_now()

    case Helper.put("systems", "fetch_timestamp:#{system_id}", timestamp) do
      {:ok, true} -> {:ok, :set}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Get the kill count for a system.
  """
  def get_kill_count(system_id) do
    case Helper.get("systems", "kill_count:#{system_id}") do
      {:ok, nil} ->
        {:ok, 0}

      {:ok, count} when is_integer(count) ->
        {:ok, count}

      {:ok, _invalid_data} ->
        # Clean up corrupted data and return 0
        Helper.delete("systems", "kill_count:#{system_id}")
        {:ok, 0}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Increment the kill count for a system.
  """
  def increment_kill_count(system_id) do
    case get_kill_count(system_id) do
      {:ok, current_count} ->
        new_count = current_count + 1

        case Helper.put("systems", "kill_count:#{system_id}", new_count) do
          {:ok, true} -> {:ok, new_count}
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get all active systems.
  """
  def get_active_systems do
    try do
      case Helper.stream("systems", "active:*") do
        {:ok, stream} ->
          # Convert stream to list and process entries
          entries = Enum.to_list(stream)
          Logger.debug("Stream entries count: #{length(entries)}")

          system_ids =
            entries
            |> Enum.map(fn entry ->
              case entry do
                # Handle the standard {key, value} format
                {key, _value} when is_binary(key) ->
                  extract_system_id_from_key(key)

                # Handle if it's just a key
                key when is_binary(key) ->
                  extract_system_id_from_key(key)

                # Handle any other format
                other ->
                  Logger.debug("Unexpected stream entry format: #{inspect(other)}")
                  nil
              end
            end)
            |> Enum.reject(&is_nil/1)
            |> Enum.sort()

          Logger.debug("Found #{length(system_ids)} active systems")
          {:ok, system_ids}

        {:error, :invalid_match} ->
          # This happens when there are no keys matching the pattern
          Logger.debug("No active systems found (no matching keys)")
          {:ok, []}

        {:error, reason} ->
          Logger.error("Failed to create systems stream: #{inspect(reason)}")
          {:error, reason}
      end
    rescue
      error ->
        Logger.error("Error processing active systems stream: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc """
  Check if a system was recently fetched.
  """
  def recently_fetched?(system_id, threshold_hours \\ 1) do
    case get_fetch_timestamp(system_id) do
      {:ok, timestamp} ->
        cutoff_time = DateTime.utc_now() |> DateTime.add(-threshold_hours * 3600, :second)
        is_recent = DateTime.compare(timestamp, cutoff_time) == :gt
        {:ok, is_recent}

      {:error, :not_found} ->
        {:ok, false}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Cache killmails for a specific system.

  This function:
  1. Updates the system's fetch timestamp
  2. Caches individual killmails by ID
  3. Associates killmail IDs with the system
  4. Adds the system to the active systems list

  ## Parameters
  - `system_id` - The solar system ID
  - `killmails` - List of killmail maps

  ## Returns
  - `:ok` on success
  - `{:error, :cache_exception}` on failure
  """
  @spec cache_killmails_for_system(integer(), [map()]) :: :ok | {:error, term()}
  def cache_killmails_for_system(system_id, killmails) when is_list(killmails) do
    # Update fetch timestamp
    case set_fetch_timestamp(system_id, DateTime.utc_now()) do
      {:ok, _} -> :ok
      # Continue anyway
      {:error, _reason} -> :ok
    end

    # Extract killmail IDs and cache individual killmails
    killmail_ids =
      for killmail <- killmails,
          killmail_id = Map.get(killmail, "killmail_id") || Map.get(killmail, "killID"),
          not is_nil(killmail_id) do
        # Cache the individual killmail
        Helper.put("killmails", to_string(killmail_id), killmail)
        killmail_id
      end

    # Add each killmail ID to system's killmail list
    Enum.each(killmail_ids, fn killmail_id ->
      add_killmail(system_id, killmail_id)
    end)

    # Add system to active list
    add_active(system_id)

    :ok
  rescue
    _error -> {:error, :cache_exception}
  end

  # Private functions

  # Helper function to extract system ID from cache key
  defp extract_system_id_from_key(key) do
    # Extract system_id from "systems:active:12345" format
    case String.split(key, ":") do
      ["systems", "active", system_id_str] ->
        case Integer.parse(system_id_str) do
          {system_id, ""} -> system_id
          _ -> nil
        end

      _ ->
        nil
    end
  end
end
