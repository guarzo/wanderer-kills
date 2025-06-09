defmodule WandererKills.Cache.EntityHelper do
  @moduledoc """
  Provides macros for entity-specific cache operations to reduce boilerplate.
  """

  defmacro __using__(_opts) do
    quote do
      import WandererKills.Cache.EntityHelper
    end
  end

  @doc """
  Defines entity-specific cache operations for a given namespace.

  ## Parameters
    - namespace: The cache namespace (e.g., "characters", "corporations")
    - entity_name: The name of the entity for function names (e.g., :character, :corporation)

  ## Example
      defmodule MyModule do
        use WandererKills.Cache.EntityHelper
        define_entity_cache("characters", :character)
      end
  """
  defmacro define_entity_cache(namespace, entity_name) do
    quote do
      @doc """
      Get #{unquote(entity_name)} data from cache.
      """
      def unquote(:"#{entity_name}_get")(id) do
        WandererKills.Cache.Helper.get_with_error(unquote(namespace), to_string(id))
      end

      @doc """
      Put #{unquote(entity_name)} data in cache.
      """
      def unquote(:"#{entity_name}_put")(id, data) do
        WandererKills.Cache.Helper.put(unquote(namespace), to_string(id), data)
      end

      @doc """
      Get or set #{unquote(entity_name)} data using a fallback function.
      """
      def unquote(:"#{entity_name}_get_or_set")(id, fallback_fn) do
        WandererKills.Cache.Helper.get_or_set(unquote(namespace), to_string(id), fallback_fn)
      end

      @doc """
      Delete #{unquote(entity_name)} data from cache.
      """
      def unquote(:"#{entity_name}_delete")(id) do
        WandererKills.Cache.Helper.delete(unquote(namespace), to_string(id))
      end
    end
  end

  @doc """
  Defines system-specific cache operations with consistent error handling patterns.

  This macro generates functions for common system cache operations like getting/setting
  lists, counts, and timestamps with consistent error handling and data validation.

  ## Parameters
    - data_type: The type of data being cached (e.g., :killmails, :kill_count, :active_list)
    - options: Keyword list of options
      - :list_type - :boolean if this caches a list that supports adding items
      - :count_type - :boolean if this caches a counter that supports incrementing
      - :timestamp_type - :boolean if this caches timestamps
      - :default_value - Default value when cache is empty (defaults to [] for lists, 0 for counts)

  ## Example
      defmodule MyModule do
        use WandererKills.Cache.EntityHelper
        define_system_cache(:killmails, list_type: true, default_value: [])
        define_system_cache(:kill_count, count_type: true, default_value: 0)
      end
  """
  defmacro define_system_cache(data_type, options \\ []) do
    config = extract_config(options, data_type)

    quote do
      unquote(generate_base_functions(data_type, config))
      unquote(generate_list_functions(data_type, config))
      unquote(generate_count_functions(data_type, config))
      unquote(generate_timestamp_functions(data_type, config))
    end
  end

  # Extract configuration from options to reduce complexity
  defp extract_config(options, data_type) do
    list_type = Keyword.get(options, :list_type, false)
    count_type = Keyword.get(options, :count_type, false)
    timestamp_type = Keyword.get(options, :timestamp_type, false)

    default_value =
      Keyword.get(options, :default_value) ||
        determine_default_value(list_type, count_type)

    cache_key = Keyword.get(options, :cache_key) || "#{data_type}"

    {list_type, count_type, timestamp_type, default_value, cache_key}
  end

  # Generate base get/set functions
  defp generate_base_functions(
         data_type,
         {list_type, count_type, timestamp_type, default_value, cache_key}
       ) do
    quote do
      @doc """
      Gets #{unquote(data_type)} for a system.
      """
      def unquote(:"system_get_#{data_type}")(system_id) do
        case WandererKills.Cache.Helper.get("systems", "#{unquote(cache_key)}:#{system_id}") do
          {:ok, nil} ->
            {:ok, unquote(default_value)}

          {:ok, data}
          when unquote(build_data_guard(list_type, count_type, timestamp_type)) ->
            {:ok, data}

          {:ok, _invalid} ->
            {:ok, unquote(default_value)}

          {:error, _reason} ->
            {:ok, unquote(default_value)}
        end
      end

      @doc """
      Sets #{unquote(data_type)} for a system.
      """
      def unquote(:"system_put_#{data_type}")(system_id, data) do
        WandererKills.Cache.Helper.put("systems", "#{unquote(cache_key)}:#{system_id}", data)
      end
    end
  end

  # Generate list-specific functions
  defp generate_list_functions(_data_type, {false, _, _, _, _}), do: quote(do: nil)

  defp generate_list_functions(data_type, _config) do
    add_function_name = data_type |> to_string() |> String.trim_trailing("s")

    quote do
      @doc """
      Adds an item to #{unquote(data_type)} list for a system.
      """
      def unquote(:"system_add_#{add_function_name}")(system_id, item) do
        case unquote(:"system_get_#{data_type}")(system_id) do
          {:ok, existing_items} ->
            if item in existing_items do
              {:ok, true}
            else
              new_items = [item | existing_items]
              unquote(:"system_put_#{data_type}")(system_id, new_items)
            end

          {:error, reason} ->
            {:error, reason}
        end
      end
    end
  end

  # Generate count-specific functions
  defp generate_count_functions(_data_type, {_, false, _, _, _}), do: quote(do: nil)

  defp generate_count_functions(data_type, _config) do
    quote do
      @doc """
      Increments #{unquote(data_type)} for a system.
      """
      def unquote(:"system_increment_#{data_type}")(system_id) do
        case unquote(:"system_get_#{data_type}")(system_id) do
          {:ok, current_count} ->
            new_count = current_count + 1

            case unquote(:"system_put_#{data_type}")(system_id, new_count) do
              {:ok, _} -> {:ok, new_count}
              error -> error
            end
        end
      end
    end
  end

  # Generate timestamp-specific functions
  defp generate_timestamp_functions(_data_type, {_, _, false, _, _}), do: quote(do: nil)

  defp generate_timestamp_functions(data_type, _config) do
    quote do
      @doc """
      Marks system with current timestamp for #{unquote(data_type)}.
      """
      def unquote(:"system_mark_#{data_type}")(system_id) do
        timestamp = System.system_time(:second)
        unquote(:"system_put_#{data_type}")(system_id, timestamp)
      end

      @doc """
      Checks if system #{unquote(data_type)} is recent (within threshold minutes).
      """
      def unquote(:"system_#{data_type}_recent?")(system_id, threshold_minutes \\ nil) do
        threshold = threshold_minutes || WandererKills.Config.cache().recent_fetch_threshold

        case unquote(:"system_get_#{data_type}")(system_id) do
          {:ok, timestamp} when is_integer(timestamp) and timestamp > 0 ->
            current_time = System.system_time(:second)
            threshold_seconds = threshold * 60
            {:ok, current_time - timestamp < threshold_seconds}

          {:ok, _} ->
            # Default value case (0) or invalid timestamp - not recent
            {:ok, false}
        end
      end
    end
  end

  # Helper functions to reduce complexity and nesting

  defp determine_default_value(true, _), do: []
  defp determine_default_value(_, true), do: 0
  defp determine_default_value(_, _), do: 0

  defp build_data_guard(true, false, false), do: quote(do: is_list(data))
  defp build_data_guard(false, true, false), do: quote(do: is_integer(data))
  defp build_data_guard(false, false, true), do: quote(do: is_integer(data))
  defp build_data_guard(_, _, _), do: quote(do: true)
end
