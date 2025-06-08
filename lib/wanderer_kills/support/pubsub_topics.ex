defmodule WandererKills.Support.PubSubTopics do
  @moduledoc """
  Centralized PubSub topic naming and management.

  This module provides a consistent API for building PubSub topic names
  used throughout the WandererKills application, eliminating repetitive
  string interpolations and reducing the chance of typos.
  """

  @doc """
  Builds a system-level topic name for basic killmail updates.

  ## Examples
      iex> WandererKills.Support.PubSubTopics.system_topic(30000142)
      "zkb:system:30000142"
  """
  @spec system_topic(integer()) :: String.t()
  def system_topic(system_id) when is_integer(system_id) do
    "zkb:system:#{system_id}"
  end

  @doc """
  Builds a detailed system-level topic name for enhanced killmail updates.

  ## Examples
      iex> WandererKills.Support.PubSubTopics.system_detailed_topic(30000142)
      "zkb:system:30000142:detailed"
  """
  @spec system_detailed_topic(integer()) :: String.t()
  def system_detailed_topic(system_id) when is_integer(system_id) do
    "zkb:system:#{system_id}:detailed"
  end

  @doc """
  Returns both system topics for a given system ID.

  This is useful when you need to subscribe/unsubscribe from both
  basic and detailed topics for the same system.

  ## Examples
      iex> WandererKills.Support.PubSubTopics.system_topics(30000142)
      ["zkb:system:30000142", "zkb:system:30000142:detailed"]
  """
  @spec system_topics(integer()) :: [String.t()]
  def system_topics(system_id) when is_integer(system_id) do
    [system_topic(system_id), system_detailed_topic(system_id)]
  end

  @doc """
  Validates that a topic follows the expected format.

  Returns `true` if the topic is a valid system topic, `false` otherwise.

  ## Examples
      iex> WandererKills.Support.PubSubTopics.valid_system_topic?("zkb:system:30000142")
      true

      iex> WandererKills.Support.PubSubTopics.valid_system_topic?("invalid:topic")
      false
  """
  @spec valid_system_topic?(String.t()) :: boolean()
  def valid_system_topic?(topic) when is_binary(topic) do
    case topic do
      "zkb:system:" <> rest ->
        case String.split(rest, ":") do
          [system_id] -> valid_system_id?(system_id)
          [system_id, "detailed"] -> valid_system_id?(system_id)
          _ -> false
        end

      _ ->
        false
    end
  end

  def valid_system_topic?(_), do: false

  @doc """
  Extracts the system ID from a system topic.

  Returns `{:ok, system_id}` if successful, `{:error, :invalid_topic}` otherwise.

  ## Examples
      iex> WandererKills.Support.PubSubTopics.extract_system_id("zkb:system:30000142")
      {:ok, 30000142}

      iex> WandererKills.Support.PubSubTopics.extract_system_id("zkb:system:30000142:detailed")
      {:ok, 30000142}

      iex> WandererKills.Support.PubSubTopics.extract_system_id("invalid:topic")
      {:error, :invalid_topic}
  """
  @spec extract_system_id(String.t()) :: {:ok, integer()} | {:error, :invalid_topic}
  def extract_system_id(topic) when is_binary(topic) do
    case topic do
      "zkb:system:" <> rest ->
        case String.split(rest, ":") do
          [system_id_str] ->
            parse_system_id(system_id_str)

          [system_id_str, "detailed"] ->
            parse_system_id(system_id_str)

          _ ->
            {:error, :invalid_topic}
        end

      _ ->
        {:error, :invalid_topic}
    end
  end

  def extract_system_id(_), do: {:error, :invalid_topic}

  # Private helper functions

  defp valid_system_id?(system_id_str) do
    case Integer.parse(system_id_str) do
      {system_id, ""} when system_id > 0 -> true
      _ -> false
    end
  end

  defp parse_system_id(system_id_str) do
    case Integer.parse(system_id_str) do
      {system_id, ""} when system_id > 0 -> {:ok, system_id}
      _ -> {:error, :invalid_topic}
    end
  end
end
