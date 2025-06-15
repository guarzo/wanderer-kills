defmodule WandererKills.Ingest.Http.Param do
  @moduledoc """
  Unified HTTP query parameter encoding and processing helper.

  Consolidates parameter handling logic that was previously duplicated
  across ESI, ZKB, and RedisQ clients.
  """

  @type param_key :: atom() | String.t()
  @type param_value :: any()
  @type param_option :: {:key_transform, :snake_to_camel | :identity}
                       | {:filter_nils, boolean()}
                       | {:string_convert, boolean()}
                       | {:validator, (param_key(), param_value() -> boolean())}

  @doc """
  Encodes parameters into a pre-encoded query string.

  ## Options

  - `:key_transform` - Transform parameter keys (`:snake_to_camel` or `:identity`)
  - `:filter_nils` - Remove nil values (default: true)
  - `:string_convert` - Convert boolean/integer values to strings (default: true)
  - `:validator` - Function to validate each parameter (default: allow all)

  ## Examples

      iex> encode([page: 1, limit: nil, active: true])
      "page=1&active=true"

      iex> encode([start_time: "2023-01-01", page: 1], key_transform: :snake_to_camel)
      "startTime=2023-01-01&page=1"

      iex> encode([page: 1, limit: 50], validator: fn :limit, v -> v <= 200 end)
      "page=1&limit=50"
  """
  @spec encode(keyword() | map(), [param_option()]) :: String.t()
  def encode(params, opts \\ []) when is_list(params) or is_map(params) do
    params
    |> process_params(opts)
    |> URI.encode_query()
  end

  @doc """
  Processes parameters according to options but returns a keyword list.

  Useful when you need the processed parameters but not the encoded string.
  """
  @spec process_params(keyword() | map(), [param_option()]) :: keyword()
  def process_params(params, opts \\ []) when is_list(params) or is_map(params) do
    key_transform = Keyword.get(opts, :key_transform, :identity)
    filter_nils = Keyword.get(opts, :filter_nils, true)
    string_convert = Keyword.get(opts, :string_convert, true)
    validator = Keyword.get(opts, :validator, fn _key, _value -> true end)

    params
    |> Enum.to_list()
    |> maybe_filter_nils(filter_nils)
    |> Enum.filter(fn {key, value} -> validator.(key, value) end)
    |> maybe_string_convert(string_convert)
    |> maybe_transform_keys(key_transform)
  end

  @doc """
  ZKB-specific parameter encoding with validation and camelCase conversion.

  Handles the specific requirements of the zKillboard API including:
  - Parameter validation (page, limit, time ranges)
  - Snake case to camelCase conversion for specific keys
  - Default parameters (no_items: true)
  """
  @spec encode_zkb_params(keyword()) :: String.t()
  def encode_zkb_params(opts) when is_list(opts) do
    base_params = [no_items: true]

    processed_params =
      opts
      |> process_params(
        key_transform: :snake_to_camel,
        validator: &zkb_param_validator/2
      )

    final_params = Keyword.merge(base_params, processed_params)
    URI.encode_query(final_params)
  end

  @doc """
  ESI-specific parameter encoding with standard filtering.
  """
  @spec encode_esi_params(keyword()) :: String.t()
  def encode_esi_params(params) when is_list(params) do
    encode(params, key_transform: :identity)
  end

  @doc """
  RedisQ-specific parameter encoding (minimal processing).
  """
  @spec encode_redisq_params(keyword()) :: String.t()
  def encode_redisq_params(params) when is_list(params) do
    encode(params, string_convert: false)
  end

  # Private helper functions

  defp maybe_filter_nils(params, true) do
    Enum.reject(params, fn {_key, value} -> is_nil(value) end)
  end

  defp maybe_filter_nils(params, false), do: params

  defp maybe_string_convert(params, true) do
    Enum.map(params, fn
      {key, true} -> {key, "true"}
      {key, false} -> {key, "false"}
      {key, value} when is_integer(value) -> {key, Integer.to_string(value)}
      {key, value} -> {key, value}
    end)
  end

  defp maybe_string_convert(params, false), do: params

  defp maybe_transform_keys(params, :snake_to_camel) do
    Enum.map(params, fn {key, value} ->
      {snake_to_camel(key), value}
    end)
  end

  defp maybe_transform_keys(params, :identity), do: params

  defp snake_to_camel(key) when is_atom(key) do
    key
    |> Atom.to_string()
    |> snake_to_camel()
    |> String.to_atom()
  end

  defp snake_to_camel(key) when is_binary(key) do
    case String.split(key, "_") do
      [single] ->
        single

      [first | rest] ->
        first <> Enum.map_join(rest, &String.capitalize/1)
    end
  end

  # ZKB-specific parameter validation
  defp zkb_param_validator(:page, page) when is_integer(page) and page > 0, do: true
  defp zkb_param_validator(:limit, limit) when is_integer(limit) and limit > 0 and limit <= 200, do: true
  defp zkb_param_validator(:start_time, start_time) when is_binary(start_time), do: true
  defp zkb_param_validator(:end_time, end_time) when is_binary(end_time), do: true
  defp zkb_param_validator(:past_seconds, seconds) when is_integer(seconds) and seconds > 0, do: true
  defp zkb_param_validator(_, _), do: false
end