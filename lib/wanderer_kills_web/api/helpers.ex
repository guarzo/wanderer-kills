defmodule WandererKillsWeb.Api.Helpers do
  @moduledoc """
  Helper functions for API controllers.
  """

  import Plug.Conn
  alias WandererKills.Core.Types
  alias WandererKills.Core.Support.Error
  alias WandererKills.Domain.Killmail

  @doc """
  Parses an integer parameter from the request.
  Returns {:ok, integer} or {:error, :invalid_id}.
  """
  @spec parse_integer_param(Plug.Conn.t(), String.t()) :: {:ok, integer()} | {:error, Error.t()}
  def parse_integer_param(conn, param_name) do
    case Map.get(conn.params, param_name) do
      nil ->
        {:error, Error.validation_error(:invalid_id, "Parameter #{param_name} is missing")}

      "" ->
        {:error, Error.validation_error(:invalid_id, "Parameter #{param_name} is empty")}

      value when is_binary(value) ->
        case Integer.parse(value) do
          {int, ""} when int > 0 ->
            {:ok, int}

          {int, ""} when int <= 0 ->
            # Allow negative numbers for some use cases
            {:ok, int}

          _ ->
            {:error,
             Error.validation_error(:invalid_id, "Parameter #{param_name} is not a valid integer")}
        end

      value when is_integer(value) ->
        {:ok, value}

      _ ->
        {:error, Error.validation_error(:invalid_id, "Parameter #{param_name} has invalid type")}
    end
  end

  @doc """
  Sends a JSON response.
  """
  @spec send_json_resp(Plug.Conn.t(), integer(), term()) :: Plug.Conn.t()
  def send_json_resp(conn, status, data) do
    # Convert structs to maps for JSON encoding
    json_data = prepare_for_json(data)
    
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(json_data))
  end

  @doc """
  Renders a success response with standard envelope format.
  """
  @spec render_success(Plug.Conn.t(), term()) :: Plug.Conn.t()
  def render_success(conn, data) do
    response = Types.success_response(data)
    send_json_resp(conn, 200, response)
  end

  @doc """
  Renders an error response with standard envelope format.
  """
  @spec render_error(Plug.Conn.t(), integer(), String.t(), String.t(), map() | nil) ::
          Plug.Conn.t()
  def render_error(conn, status_code, message, error_code, details \\ nil) do
    response = Types.error_response(message, error_code, details)
    send_json_resp(conn, status_code, response)
  end

  @doc """
  Validates and parses system_id parameter.
  """
  @spec validate_system_id(String.t()) :: {:ok, integer()} | {:error, Error.t()}
  def validate_system_id(system_id_str) when is_binary(system_id_str) do
    case Integer.parse(system_id_str) do
      {system_id, ""} when system_id > 0 ->
        {:ok, system_id}

      _ ->
        {:error, Error.validation_error(:invalid_format, "System ID must be a positive integer")}
    end
  end

  def validate_system_id(_),
    do: {:error, Error.validation_error(:invalid_format, "System ID must be a string")}

  @doc """
  Validates and parses killmail_id parameter.
  """
  @spec validate_killmail_id(String.t()) :: {:ok, integer()} | {:error, Error.t()}
  def validate_killmail_id(killmail_id_str) when is_binary(killmail_id_str) do
    case Integer.parse(killmail_id_str) do
      {killmail_id, ""} when killmail_id > 0 ->
        {:ok, killmail_id}

      _ ->
        {:error,
         Error.validation_error(:invalid_format, "Killmail ID must be a positive integer")}
    end
  end

  def validate_killmail_id(_),
    do: {:error, Error.validation_error(:invalid_format, "Killmail ID must be a string")}

  @doc """
  Validates and parses since_hours parameter.
  """
  @spec validate_since_hours(String.t() | integer()) ::
          {:ok, integer()} | {:error, Error.t()}
  def validate_since_hours(since_hours) when is_integer(since_hours) and since_hours > 0 do
    {:ok, since_hours}
  end

  def validate_since_hours(since_hours_str) when is_binary(since_hours_str) do
    case Integer.parse(since_hours_str) do
      {since_hours, ""} when since_hours > 0 ->
        {:ok, since_hours}

      _ ->
        {:error,
         Error.validation_error(:invalid_format, "Since hours must be a positive integer")}
    end
  end

  def validate_since_hours(_),
    do: {:error, Error.validation_error(:invalid_format, "Since hours has invalid type")}

  @doc """
  Validates and parses limit parameter.
  """
  @spec validate_limit(String.t() | integer() | nil) ::
          {:ok, integer()} | {:error, Error.t()}
  # default limit
  def validate_limit(nil), do: {:ok, 50}

  def validate_limit(limit) when is_integer(limit) and limit > 0 and limit <= 1000 do
    {:ok, limit}
  end

  def validate_limit(limit_str) when is_binary(limit_str) do
    case Integer.parse(limit_str) do
      {limit, ""} when limit > 0 and limit <= 1000 ->
        {:ok, limit}

      _ ->
        {:error, Error.validation_error(:invalid_format, "Limit must be between 1 and 1000")}
    end
  end

  def validate_limit(_),
    do: {:error, Error.validation_error(:invalid_format, "Limit has invalid type")}

  @doc """
  Validates system_ids array from request body.
  """
  @spec validate_system_ids(list() | nil) :: {:ok, [integer()]} | {:error, Error.t()}
  def validate_system_ids(system_ids) when is_list(system_ids) do
    if Enum.all?(system_ids, &is_integer/1) and not Enum.empty?(system_ids) do
      {:ok, system_ids}
    else
      {:error,
       Error.validation_error(
         :invalid_system_ids,
         "System IDs must be a non-empty list of integers"
       )}
    end
  end

  def validate_system_ids(_),
    do: {:error, Error.validation_error(:invalid_system_ids, "System IDs must be a list")}

  @doc """
  Validates subscriber_id parameter.
  """
  @spec validate_subscriber_id(String.t() | nil) ::
          {:ok, String.t()} | {:error, Error.t()}
  def validate_subscriber_id(subscriber_id) when is_binary(subscriber_id) do
    if String.trim(subscriber_id) != "" do
      {:ok, String.trim(subscriber_id)}
    else
      {:error, Error.validation_error(:invalid_subscriber_id, "Subscriber ID cannot be empty")}
    end
  end

  def validate_subscriber_id(_),
    do: {:error, Error.validation_error(:invalid_subscriber_id, "Subscriber ID must be a string")}

  @doc """
  Validates callback_url parameter (optional).
  """
  @spec validate_callback_url(String.t() | nil) ::
          {:ok, String.t() | nil} | {:error, Error.t()}
  def validate_callback_url(nil), do: {:ok, nil}

  def validate_callback_url(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and not is_nil(host) ->
        {:ok, url}

      _ ->
        {:error,
         Error.validation_error(
           :invalid_callback_url,
           "Callback URL must be a valid HTTP/HTTPS URL"
         )}
    end
  end

  def validate_callback_url(_),
    do: {:error, Error.validation_error(:invalid_callback_url, "Callback URL must be a string")}

  # Private helper to convert structs to maps for JSON encoding
  defp prepare_for_json(%Killmail{} = killmail), do: Killmail.to_map(killmail)
  defp prepare_for_json(list) when is_list(list) do
    Enum.map(list, &prepare_for_json/1)
  end
  defp prepare_for_json(%{__struct__: _} = struct) do
    # Generic struct handling - convert to map
    Map.from_struct(struct)
  end
  defp prepare_for_json(data), do: data
end
