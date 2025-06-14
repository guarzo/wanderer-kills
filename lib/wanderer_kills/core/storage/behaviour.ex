defmodule WandererKills.Core.Storage.Behaviour do
  @moduledoc """
  Behaviour for killmail storage implementations.

  This behaviour defines the contract for all killmail storage modules,
  ensuring consistent API regardless of the underlying storage mechanism.
  """

  alias WandererKills.Core.Support.Error

  @type killmail_id :: integer()
  @type system_id :: integer()
  @type killmail_data :: map()
  @type event_id :: integer()
  @type client_id :: term()
  @type client_offsets :: %{system_id() => event_id()}
  @type event_tuple :: {event_id(), system_id(), killmail_data()}

  # Core Storage Operations
  @callback put(killmail_id(), killmail_data()) :: :ok | {:error, Error.t()}
  @callback put(killmail_id(), system_id(), killmail_data()) :: :ok | {:error, Error.t()}
  @callback get(killmail_id()) :: {:ok, killmail_data()} | {:error, Error.t()}
  @callback delete(killmail_id()) :: :ok
  @callback list_by_system(system_id()) :: [killmail_data()]

  # System Operations
  @callback add_system_killmail(system_id(), killmail_id()) :: :ok
  @callback get_killmails_for_system(system_id()) :: {:ok, [killmail_id()]}
  @callback remove_system_killmail(system_id(), killmail_id()) :: :ok
  @callback increment_system_killmail_count(system_id()) :: :ok
  @callback get_system_killmail_count(system_id()) :: {:ok, non_neg_integer()}

  # Timestamp Operations
  @callback set_system_fetch_timestamp(system_id(), DateTime.t()) :: :ok
  @callback get_system_fetch_timestamp(system_id()) :: {:ok, DateTime.t()} | {:error, Error.t()}

  # Event Streaming Operations (optional)
  @callback insert_event(system_id(), killmail_data()) :: :ok
  @callback fetch_for_client(client_id(), [system_id()]) :: {:ok, [event_tuple()]}
  @callback fetch_one_event(client_id(), system_id() | [system_id()]) ::
              {:ok, event_tuple()} | :empty
  @callback get_client_offsets(client_id()) :: client_offsets()
  @callback put_client_offsets(client_id(), client_offsets()) :: :ok

  # Maintenance Operations
  @callback clear() :: :ok
  @callback init_tables!() :: :ok

  @optional_callbacks [
    insert_event: 2,
    fetch_for_client: 2,
    fetch_one_event: 2,
    get_client_offsets: 1,
    put_client_offsets: 2
  ]
end
