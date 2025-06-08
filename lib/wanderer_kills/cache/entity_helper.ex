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
end
