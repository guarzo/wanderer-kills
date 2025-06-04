defmodule WandererKills.Esi.Types do
  @moduledoc """
  Defines structs for ESI API responses.
  """

  @type t :: CharacterInfo | CorporationInfo | AllianceInfo | TypeInfo | GroupInfo | SystemInfo

  defmodule CharacterInfo do
    @moduledoc """
    Represents character information from ESI.
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
    Represents corporation information from ESI.
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
    Represents alliance information from ESI.
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
    Represents type information from ESI.
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
    Represents group information from ESI.
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
    Represents solar system information from ESI.
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
