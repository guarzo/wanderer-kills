if Mix.env() == :test do
  defmodule WandererKills.Core.MockHttpClient do
    @moduledoc """
    Mock HTTP client for testing.

    This module provides a basic implementation that can be overridden
    by Mox expectations in tests.
    """

    @behaviour WandererKills.Http.ClientBehaviour

    @impl true
    def get_with_rate_limit(_url, opts) do
      # Check if this is a raw request (for file downloads)
      if Keyword.get(opts, :raw, false) do
        # For raw requests, return binary data
        {:ok, %{status_code: 200, body: "mock file content"}}
      else
        # For API requests, return JSON structure
        {:ok, %{status_code: 200, body: %{"name" => "mock_name", "id" => 123}}}
      end
    end

    @impl true
    def handle_status_code(200, response) do
      {:ok, response}
    end

    def handle_status_code(status_code, _response) do
      {:error, {:http_error, status_code}}
    end
  end
end
