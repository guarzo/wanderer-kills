defmodule WandererKills.Killmails.FieldNormalizer do
  @moduledoc """
  Normalizes killmail field names to consistent internal format.

  This module handles the conversion from various external formats
  (e.g., zKillboard's "killID") to our standardized internal format.
  """

  @doc """
  Normalizes a killmail's field names to our standard format.

  Conversions:
  - "killID" -> "killmail_id"
  - "killmail_time" -> "kill_time"
  """
  @spec normalize_killmail(map()) :: map()
  def normalize_killmail(killmail) when is_map(killmail) do
    killmail
    |> normalize_kill_id()
    |> normalize_kill_time()
  end

  @doc """
  Normalizes a list of killmails.
  """
  @spec normalize_killmails([map()]) :: [map()]
  def normalize_killmails(killmails) when is_list(killmails) do
    Enum.map(killmails, &normalize_killmail/1)
  end

  # Normalize kill ID fields
  defp normalize_kill_id(%{"killID" => id} = killmail)
       when not is_map_key(killmail, "killmail_id") do
    killmail
    |> Map.put("killmail_id", id)
    |> Map.delete("killID")
  end

  defp normalize_kill_id(killmail), do: killmail

  # Normalize time fields
  defp normalize_kill_time(%{"killmail_time" => time} = killmail)
       when not is_map_key(killmail, "kill_time") do
    killmail
    |> Map.put("kill_time", time)
    |> Map.delete("killmail_time")
  end

  defp normalize_kill_time(killmail), do: killmail
end
