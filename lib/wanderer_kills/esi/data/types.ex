defmodule WandererKills.Esi.Data.Types do
  @moduledoc """
  Defines structs for ESI API responses.

  This module contains all the data structures used to represent
  information retrieved from the EVE Swagger Interface (ESI) API.

  ## Available Types

  - `CharacterInfo` - Character data from `/characters/{character_id}/`
  - `CorporationInfo` - Corporation data from `/corporations/{corporation_id}/`
  - `AllianceInfo` - Alliance data from `/alliances/{alliance_id}/`
  - `TypeInfo` - Item type data from `/universe/types/{type_id}/`
  - `GroupInfo` - Item group data from `/universe/groups/{group_id}/`
  - `SystemInfo` - Solar system data from `/universe/systems/{system_id}/`

  ## Usage

  ```elixir
  alias WandererKills.Esi.Data.Types

  # Use specific type
  character = %Types.CharacterInfo{character_id: 12345, name: "Player Name"}

  # Or use the umbrella type for function specs
  @spec process_esi_data(Types.t()) :: term()
  ```
  """

  @type t ::
          CharacterInfo.t()
          | CorporationInfo.t()
          | AllianceInfo.t()
          | TypeInfo.t()
          | GroupInfo.t()
          | SystemInfo.t()

  defmodule CharacterInfo do
    @moduledoc """
    Represents character information from ESI `/characters/{character_id}/` endpoint.

    ## Fields

    - `character_id` - The character's unique ID
    - `name` - The character's name
    - `corporation_id` - ID of the character's corporation
    - `alliance_id` - ID of the character's alliance (if any)
    - `faction_id` - ID of the character's faction (if any)
    - `security_status` - The character's security status
    """
    @type t :: %__MODULE__{
            character_id: integer(),
            name: String.t(),
            corporation_id: integer(),
            alliance_id: integer() | nil,
            faction_id: integer() | nil,
            security_status: float() | nil
          }

    defstruct [
      :character_id,
      :name,
      :corporation_id,
      :alliance_id,
      :faction_id,
      :security_status
    ]
  end

  defmodule CorporationInfo do
    @moduledoc """
    Represents corporation information from ESI `/corporations/{corporation_id}/` endpoint.

    ## Fields

    - `corporation_id` - The corporation's unique ID
    - `name` - The corporation's name
    - `alliance_id` - ID of the corporation's alliance (if any)
    - `faction_id` - ID of the corporation's faction (if any)
    - `ticker` - The corporation's ticker symbol
    - `member_count` - Number of members in the corporation
    - `ceo_id` - Character ID of the corporation's CEO
    """
    @type t :: %__MODULE__{
            corporation_id: integer(),
            name: String.t(),
            alliance_id: integer() | nil,
            faction_id: integer() | nil,
            ticker: String.t(),
            member_count: integer() | nil,
            ceo_id: integer() | nil
          }

    defstruct [
      :corporation_id,
      :name,
      :alliance_id,
      :faction_id,
      :ticker,
      :member_count,
      :ceo_id
    ]
  end

  defmodule AllianceInfo do
    @moduledoc """
    Represents alliance information from ESI `/alliances/{alliance_id}/` endpoint.

    ## Fields

    - `alliance_id` - The alliance's unique ID
    - `name` - The alliance's name
    - `ticker` - The alliance's ticker symbol
    - `creator_corporation_id` - ID of the corporation that created the alliance
    - `creator_id` - Character ID of the alliance creator
    - `date_founded` - Date the alliance was founded
    - `executor_corporation_id` - ID of the alliance's executor corporation
    """
    @type t :: %__MODULE__{
            alliance_id: integer(),
            name: String.t(),
            ticker: String.t(),
            creator_corporation_id: integer() | nil,
            creator_id: integer() | nil,
            date_founded: String.t() | nil,
            executor_corporation_id: integer() | nil
          }

    defstruct [
      :alliance_id,
      :name,
      :ticker,
      :creator_corporation_id,
      :creator_id,
      :date_founded,
      :executor_corporation_id
    ]
  end

  defmodule TypeInfo do
    @moduledoc """
    Represents item type information from ESI `/universe/types/{type_id}/` endpoint.

    This includes ships, modules, ammunition, and other items in EVE Online.

    ## Fields

    - `type_id` - The type's unique ID
    - `name` - The type's name
    - `description` - Description of the type
    - `group_id` - ID of the group this type belongs to
    - `market_group_id` - ID of the market group (if tradeable)
    - `mass` - Mass of the item in kg
    - `packaged_volume` - Volume when packaged in m³
    - `portion_size` - Portion size for consumables
    - `published` - Whether this type is published in-game
    - `radius` - Radius of the item in meters
    - `volume` - Volume of the item in m³
    """
    @type t :: %__MODULE__{
            type_id: integer(),
            name: String.t(),
            description: String.t() | nil,
            group_id: integer(),
            market_group_id: integer() | nil,
            mass: float() | nil,
            packaged_volume: float() | nil,
            portion_size: integer() | nil,
            published: boolean(),
            radius: float() | nil,
            volume: float() | nil
          }

    defstruct [
      :type_id,
      :name,
      :description,
      :group_id,
      :market_group_id,
      :mass,
      :packaged_volume,
      :portion_size,
      :published,
      :radius,
      :volume
    ]
  end

  defmodule GroupInfo do
    @moduledoc """
    Represents item group information from ESI `/universe/groups/{group_id}/` endpoint.

    Groups contain related item types (e.g., "Frigates", "Battleships").

    ## Fields

    - `group_id` - The group's unique ID
    - `name` - The group's name
    - `category_id` - ID of the category this group belongs to
    - `published` - Whether this group is published in-game
    - `types` - List of type IDs in this group
    """
    @type t :: %__MODULE__{
            group_id: integer(),
            name: String.t(),
            category_id: integer(),
            published: boolean(),
            types: [integer()] | nil
          }

    defstruct [
      :group_id,
      :name,
      :category_id,
      :published,
      :types
    ]
  end

  defmodule SystemInfo do
    @moduledoc """
    Represents solar system information from ESI `/universe/systems/{system_id}/` endpoint.

    ## Fields

    - `system_id` - The system's unique ID
    - `name` - The system's name
    - `constellation_id` - ID of the constellation this system belongs to
    - `security_status` - Security status of the system (0.0 to 1.0)
    - `star_id` - ID of the system's star
    """
    @type t :: %__MODULE__{
            system_id: integer(),
            name: String.t(),
            constellation_id: integer(),
            security_status: float(),
            star_id: integer() | nil
          }

    defstruct [
      :system_id,
      :name,
      :constellation_id,
      :security_status,
      :star_id
    ]
  end
end
