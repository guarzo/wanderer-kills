defmodule WandererKills.ESI.ClientBehaviour do
  @moduledoc """
  Behaviour for ESI (EVE Swagger Interface) client implementations.

  This behaviour standardizes interactions with the EVE Online ESI API,
  providing both type-specific methods and a generic fetch interface.
  """

  alias WandererKills.Support.Error

  @type entity_id :: pos_integer()
  @type entity_data :: map()
  @type esi_result :: {:ok, entity_data()} | {:error, Error.t()}
  @type fetch_args :: term()

  # Character operations
  @callback get_character(entity_id()) :: esi_result()
  @callback get_character_batch([entity_id()]) :: [esi_result()]

  # Corporation operations
  @callback get_corporation(entity_id()) :: esi_result()
  @callback get_corporation_batch([entity_id()]) :: [esi_result()]

  # Alliance operations
  @callback get_alliance(entity_id()) :: esi_result()
  @callback get_alliance_batch([entity_id()]) :: [esi_result()]

  # Type operations
  @callback get_type(entity_id()) :: esi_result()
  @callback get_type_batch([entity_id()]) :: [esi_result()]

  # Group operations
  @callback get_group(entity_id()) :: esi_result()
  @callback get_group_batch([entity_id()]) :: [esi_result()]

  # System operations
  @callback get_system(entity_id()) :: esi_result()
  @callback get_system_batch([entity_id()]) :: [esi_result()]

  # Generic fetch operation (for flexibility)
  @callback fetch(fetch_args()) :: esi_result()
end
