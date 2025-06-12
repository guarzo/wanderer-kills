defmodule WandererKills.Subscriptions.WebhookNotifierTest do
  use ExUnit.Case, async: false

  alias WandererKills.Subscriptions.WebhookNotifier
  alias WandererKills.Support.Error

  import Mox

  setup :verify_on_exit!

  describe "notify_webhook/4" do
    test "successfully sends webhook notification" do
      subscription = %{
        "id" => "sub_123",
        "callback_url" => "https://example.com/webhook",
        "subscriber_id" => "user_123"
      }

      kills = [
        %{
          "killmail_id" => 123_456,
          "solar_system_id" => 30_000_142,
          "killmail_time" => "2024-01-01T00:00:00Z"
        }
      ]

      WandererKills.Http.Client.Mock
      |> expect(:post, fn url, body, opts ->
        assert url == "https://example.com/webhook"
        assert body[:type] == "killmail_update"
        assert body[:system_id] == 30_000_142
        assert body[:kills] == kills

        assert opts[:headers] == [
                 {"Content-Type", "application/json"},
                 {"User-Agent", "WandererKills/1.0"}
               ]

        {:ok, %{status: 200, body: %{"success" => true}}}
      end)

      assert :ok =
               WebhookNotifier.notify_webhook(
                 subscription["callback_url"],
                 30_000_142,
                 kills,
                 subscription["id"]
               )
    end

    test "handles webhook failure gracefully" do
      subscription = %{
        "id" => "sub_123",
        "callback_url" => "https://example.com/webhook",
        "subscriber_id" => "user_123"
      }

      kills = [%{"killmail_id" => 123_456}]

      WandererKills.Http.Client.Mock
      |> expect(:post, fn _url, _body, _opts ->
        {:error, Error.http_error(:timeout, "Request timed out", true)}
      end)

      # Should return an error tuple
      assert {:error, _} =
               WebhookNotifier.notify_webhook(
                 subscription["callback_url"],
                 30_000_142,
                 kills,
                 subscription["id"]
               )
    end

    test "handles missing callback URL" do
      subscription = %{
        "id" => "sub_123",
        "callback_url" => nil,
        "subscriber_id" => "user_123"
      }

      kills = [%{"killmail_id" => 123_456}]

      # Explicitly expect no HTTP calls
      WandererKills.Http.Client.Mock
      |> expect(:post, 0, fn _url, _body, _opts ->
        flunk("Should not make HTTP request for nil URL")
      end)

      assert :ok =
               WebhookNotifier.notify_webhook(
                 subscription["callback_url"],
                 30_000_142,
                 kills,
                 subscription["id"]
               )
    end

    test "handles empty callback URL" do
      subscription = %{
        "id" => "sub_123",
        "callback_url" => "",
        "subscriber_id" => "user_123"
      }

      kills = [%{"killmail_id" => 123_456}]

      # Explicitly expect no HTTP calls
      WandererKills.Http.Client.Mock
      |> expect(:post, 0, fn _url, _body, _opts ->
        flunk("Should not make HTTP request for empty URL")
      end)

      assert :ok =
               WebhookNotifier.notify_webhook(
                 subscription["callback_url"],
                 30_000_142,
                 kills,
                 subscription["id"]
               )
    end
  end

  describe "notify_webhook_count/4" do
    test "successfully sends kill count notification" do
      subscription = %{
        "id" => "sub_123",
        "callback_url" => "https://example.com/webhook",
        "subscriber_id" => "user_123"
      }

      WandererKills.Http.Client.Mock
      |> expect(:post, fn url, body, opts ->
        assert url == "https://example.com/webhook"
        assert body[:type] == "killmail_count_update"
        assert body[:system_id] == 30_000_142
        assert body[:count] == 42

        assert opts[:headers] == [
                 {"Content-Type", "application/json"},
                 {"User-Agent", "WandererKills/1.0"}
               ]

        {:ok, %{status: 200, body: %{"success" => true}}}
      end)

      assert :ok =
               WebhookNotifier.notify_webhook_count(
                 subscription["callback_url"],
                 30_000_142,
                 42,
                 subscription["id"]
               )
    end

    test "handles kill count notification failure" do
      subscription = %{
        "id" => "sub_123",
        "callback_url" => "https://example.com/webhook",
        "subscriber_id" => "user_123"
      }

      WandererKills.Http.Client.Mock
      |> expect(:post, fn _url, _body, _opts ->
        {:error, Error.http_error(:server_error, "Internal server error", true)}
      end)

      # Should return an error tuple
      assert {:error, _} =
               WebhookNotifier.notify_webhook_count(
                 subscription["callback_url"],
                 30_000_142,
                 42,
                 subscription["id"]
               )
    end
  end

  describe "webhook payload structure" do
    test "includes all required fields in killmail update" do
      subscription = %{
        "id" => "sub_123",
        "callback_url" => "https://example.com/webhook",
        "subscriber_id" => "user_123"
      }

      kills = [
        %{
          "killmail_id" => 123_456,
          "solar_system_id" => 30_000_142,
          "killmail_time" => "2024-01-01T00:00:00Z",
          "victim" => %{"ship_type_id" => 587}
        }
      ]

      WandererKills.Http.Client.Mock
      |> expect(:post, fn _url, body, _opts ->
        # Verify payload structure
        assert Map.has_key?(body, :type)
        assert Map.has_key?(body, :timestamp)
        assert Map.has_key?(body, :system_id)
        assert Map.has_key?(body, :kills)
        assert is_list(body[:kills])

        {:ok, %{status: 200, body: %{"success" => true}}}
      end)

      assert :ok =
               WebhookNotifier.notify_webhook(
                 subscription["callback_url"],
                 30_000_142,
                 kills,
                 subscription["id"]
               )
    end

    test "includes timestamp in ISO8601 format" do
      subscription = %{
        "id" => "sub_123",
        "callback_url" => "https://example.com/webhook",
        "subscriber_id" => "user_123"
      }

      WandererKills.Http.Client.Mock
      |> expect(:post, fn _url, body, _opts ->
        timestamp = body[:timestamp]
        assert is_binary(timestamp)
        # Should be parseable as DateTime
        assert {:ok, _datetime, _offset} = DateTime.from_iso8601(timestamp)

        {:ok, %{status: 200, body: %{"success" => true}}}
      end)

      assert :ok =
               WebhookNotifier.notify_webhook_count(
                 subscription["callback_url"],
                 30_000_142,
                 42,
                 subscription["id"]
               )
    end
  end

  describe "HTTP client options" do
    test "uses appropriate timeout for webhook requests" do
      subscription = %{
        "id" => "sub_123",
        "callback_url" => "https://example.com/webhook",
        "subscriber_id" => "user_123"
      }

      WandererKills.Http.Client.Mock
      |> expect(:post, fn _url, _body, opts ->
        # Should have a reasonable timeout
        assert opts[:timeout] >= 5000
        assert opts[:timeout] <= 30_000

        {:ok, %{status: 200, body: %{"success" => true}}}
      end)

      assert :ok =
               WebhookNotifier.notify_webhook_count(
                 subscription["callback_url"],
                 30_000_142,
                 42,
                 subscription["id"]
               )
    end
  end
end
