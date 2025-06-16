defmodule WandererKills.Test.EtsHelpers do
  @moduledoc """
  Helper functions for ETS table management in tests.

  Provides utilities for creating unique table names and managing
  ETS tables in parallel test environments.
  """

  @doc """
  Creates a unique table name for testing based on a base name and test ID.

  ## Examples

      iex> create_unique_table_name(:killmails, 123)
      :killmails_123
      
      iex> create_unique_table_name("system_killmails", 456)
      :system_killmails_456
  """
  def create_unique_table_name(base_name, test_id) when is_atom(base_name) do
    base_name
    |> Atom.to_string()
    |> create_unique_table_name(test_id)
  end

  def create_unique_table_name(base_name, test_id) when is_binary(base_name) do
    # We need to create dynamic atoms for test table names
    # This is safe because it's only used in test environments
    # and the number of atoms is limited by the number of tests
    # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
    String.to_atom("#{base_name}_#{test_id}")
  end

  @doc """
  Creates a unique ETS table for testing.

  Returns the table name that was created.
  """
  def create_test_table(base_name, test_id, opts \\ []) do
    table_name = create_unique_table_name(base_name, test_id)
    default_opts = [:set, :public, {:read_concurrency, true}]

    table_opts = Keyword.merge(default_opts, opts)

    :ets.new(table_name, table_opts)
    table_name
  end

  @doc """
  Gets the current test's unique ID from the process dictionary.

  Returns the unique ID set by `with_unique_tables/1`, or generates
  a new one if none exists.
  """
  def get_test_id do
    case Process.get(:test_unique_id) do
      nil ->
        # Generate a new unique ID and store it
        unique_id = System.unique_integer([:positive])
        Process.put(:test_unique_id, unique_id)
        unique_id

      id ->
        id
    end
  end

  @doc """
  Creates a table name unique to the current test.

  Uses the test ID from the process dictionary to ensure uniqueness.
  """
  def create_test_table_name(base_name) do
    test_id = get_test_id()
    create_unique_table_name(base_name, test_id)
  end

  @doc """
  Checks if a table exists.
  """
  def table_exists?(table_name) do
    case :ets.info(table_name) do
      :undefined -> false
      _ -> true
    end
  end

  @doc """
  Safely deletes an ETS table if it exists.
  """
  def safe_delete_table(table_name) do
    case :ets.info(table_name) do
      :undefined ->
        :ok

      _ ->
        :ets.delete(table_name)
        :ok
    end
  end

  @doc """
  Deletes all tables matching a test ID pattern.
  """
  def cleanup_test_tables(test_id) do
    # Get all ETS tables
    all_tables = :ets.all()

    # Filter tables that match our test ID pattern
    test_tables =
      Enum.filter(all_tables, fn table_name ->
        table_name_str = Atom.to_string(table_name)
        String.ends_with?(table_name_str, "_#{test_id}")
      end)

    # Delete the matching tables
    Enum.each(test_tables, &safe_delete_table/1)

    length(test_tables)
  end
end
