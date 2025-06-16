defmodule WandererKills.Subs.SubscriptionRegistry do
  @moduledoc """
  Registry for subscription worker processes.

  Provides efficient lookup of subscription workers by subscription ID.
  Used in conjunction with the DynamicSupervisor for managing individual
  subscription processes.
  """

  @doc """
  Starts the subscription registry.
  """
  @spec start_link(term()) :: GenServer.on_start()
  def start_link(_) do
    Registry.start_link(keys: :unique, name: __MODULE__)
  end

  @doc """
  Child specification for inclusion in supervision tree.
  """
  @spec child_spec(term()) :: Supervisor.child_spec()
  def child_spec(_) do
    Supervisor.child_spec(
      Registry,
      id: __MODULE__,
      start: {__MODULE__, :start_link, [[]]}
    )
  end
end
