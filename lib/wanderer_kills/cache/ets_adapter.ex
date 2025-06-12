defmodule WandererKills.Cache.ETSAdapter do
  @moduledoc """
  ETS-based cache implementation for testing.
  
  This adapter provides a simple, reliable cache implementation using ETS
  that doesn't have the external dependencies and race conditions of Cachex.
  
  Perfect for test environments where we need predictable cache behavior.
  """

  @behaviour WandererKills.Cache.Behaviour

  @impl true
  def get(cache_name, key) do
    case :ets.info(cache_name) do
      :undefined ->
        # Create table if it doesn't exist
        create_table(cache_name)
        {:ok, nil}
      
      _ ->
        case :ets.lookup(cache_name, key) do
          [{^key, value, expires_at}] ->
            if expires_at == :infinity or :os.system_time(:millisecond) < expires_at do
              {:ok, value}
            else
              # Expired entry, delete it
              :ets.delete(cache_name, key)
              {:ok, nil}
            end
          
          [] ->
            {:ok, nil}
        end
    end
  rescue
    error ->
      {:error, error}
  end

  @impl true
  def put(cache_name, key, value, opts \\ []) do
    case :ets.info(cache_name) do
      :undefined ->
        create_table(cache_name)
      
      table_info ->
        # Check if table has wrong keypos and recreate if needed
        keypos = Keyword.get(table_info, :keypos, 1)
        if keypos != 1 do
          :ets.delete(cache_name)
          create_table(cache_name)
        end
    end

    ttl = Keyword.get(opts, :ttl, :infinity)
    expires_at = if ttl == :infinity do
      :infinity
    else
      :os.system_time(:millisecond) + ttl
    end

    case :ets.insert(cache_name, {key, value, expires_at}) do
      true -> {:ok, true}
      false -> {:error, :insert_failed}
    end
  rescue
    error ->
      {:error, error}
  end

  @impl true
  def del(cache_name, key) do
    case :ets.info(cache_name) do
      :undefined ->
        {:ok, false}
      
      _ ->
        existed = :ets.member(cache_name, key)
        :ets.delete(cache_name, key)
        {:ok, existed}
    end
  rescue
    error ->
      {:error, error}
  end

  @impl true
  def exists?(cache_name, key) do
    case :ets.info(cache_name) do
      :undefined ->
        {:ok, false}
      
      _ ->
        case :ets.lookup(cache_name, key) do
          [{^key, _value, expires_at}] ->
            if expires_at == :infinity or :os.system_time(:millisecond) < expires_at do
              {:ok, true}
            else
              # Expired entry, delete it
              :ets.delete(cache_name, key)
              {:ok, false}
            end
          
          [] ->
            {:ok, false}
        end
    end
  rescue
    error ->
      {:error, error}
  end

  @impl true
  def clear(cache_name) do
    case :ets.info(cache_name) do
      :undefined ->
        {:ok, 0}
      
      _ ->
        count = :ets.info(cache_name, :size) || 0
        :ets.delete_all_objects(cache_name)
        {:ok, count}
    end
  rescue
    error ->
      {:error, error}
  end

  @impl true
  def size(cache_name) do
    case :ets.info(cache_name) do
      :undefined ->
        {:ok, 0}
      
      _ ->
        # Clean up expired entries first
        cleanup_expired(cache_name)
        size = :ets.info(cache_name, :size) || 0
        {:ok, size}
    end
  rescue
    error ->
      {:error, error}
  end

  # Private helper functions

  defp create_table(cache_name) do
    :ets.new(cache_name, [
      :set,
      :named_table,
      :public,
      {:read_concurrency, true},
      {:write_concurrency, true},
      {:keypos, 1}  # Explicitly set key position to 1 (first element)
    ])
  end

  defp cleanup_expired(cache_name) do
    now = :os.system_time(:millisecond)
    
    # Find expired entries
    expired_keys = :ets.foldl(fn
      {_key, _value, :infinity}, acc -> acc
      {key, _value, expires_at}, acc when expires_at < now -> [key | acc]
      {_key, _value, _expires_at}, acc -> acc
    end, [], cache_name)

    # Delete expired entries
    Enum.each(expired_keys, fn expired_key ->
      :ets.delete(cache_name, expired_key)
    end)
  end
end