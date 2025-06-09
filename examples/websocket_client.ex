defmodule WandererKills.WebSocketClient do
  @moduledoc """
  Elixir WebSocket client for WandererKills real-time killmail subscriptions.

  This example shows how to connect to the WandererKills WebSocket API
  from within Elixir to receive real-time killmail updates for specific
  EVE Online systems.

  ## Usage

      # Start the client
      {:ok, pid} = WandererKills.WebSocketClient.start_link([
        server_url: "ws://localhost:4004",
        systems: [30000142, 30002187]  # Jita, Amarr
      ])

      # Subscribe to additional systems
      WandererKills.WebSocketClient.subscribe_to_systems(pid, [30002659]) # Dodixie

      # Unsubscribe from systems
      WandererKills.WebSocketClient.unsubscribe_from_systems(pid, [30000142])

      # Get current status
      WandererKills.WebSocketClient.get_status(pid)

      # Stop the client
      WandererKills.WebSocketClient.stop(pid)
  """

  use GenServer
  require Logger

  alias Phoenix.Channels.GenSocketClient

  @behaviour GenSocketClient

  # Client API

  @doc """
  Start the WebSocket client.

  ## Options

    * `:server_url` - WebSocket server URL (required)
    * `:systems` - Initial systems to subscribe to (optional)
    * `:name` - Process name (optional)
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Subscribe to additional EVE Online systems.
  """
  @spec subscribe_to_systems(pid() | atom(), [integer()]) :: :ok
  def subscribe_to_systems(client, system_ids) when is_list(system_ids) do
    GenServer.cast(client, {:subscribe_systems, system_ids})
  end

  @doc """
  Unsubscribe from EVE Online systems.
  """
  @spec unsubscribe_from_systems(pid() | atom(), [integer()]) :: :ok
  def unsubscribe_from_systems(client, system_ids) when is_list(system_ids) do
    GenServer.cast(client, {:unsubscribe_systems, system_ids})
  end

  @doc """
  Get current subscription status.
  """
  @spec get_status(pid() | atom()) :: {:ok, map()} | {:error, term()}
  def get_status(client) do
    GenServer.call(client, :get_status)
  end

  @doc """
  Stop the WebSocket client.
  """
  @spec stop(pid() | atom()) :: :ok
  def stop(client) do
    GenServer.stop(client)
  end

  # GenServer Callbacks

  @impl true
  def init(opts) do
    server_url = Keyword.fetch!(opts, :server_url)
    initial_systems = Keyword.get(opts, :systems, [])

    # Convert HTTP URL to WebSocket URL if needed
    websocket_url =
      server_url
      |> String.replace("http://", "ws://")
      |> String.replace("https://", "wss://")

    state = %{
      server_url: websocket_url,
      socket: nil,
      channel: nil,
      subscribed_systems: MapSet.new(),
      initial_systems: initial_systems,
      subscription_id: nil,
      connected: false
    }

    Logger.info("🚀 Starting WandererKills WebSocket client",
      server_url: websocket_url,
      initial_systems: initial_systems
    )

    # Connect asynchronously
    send(self(), :connect)

    {:ok, state}
  end

  @impl true
  def handle_info(:connect, state) do
    case connect_to_websocket(state) do
      {:ok, socket} ->
        Logger.info("✅ Connected to WandererKills WebSocket")

        # Join the killmails channel
        case join_channel(socket, state.initial_systems) do
          {:ok, channel} ->
            new_state = %{state |
              socket: socket,
              channel: channel,
              connected: true,
              subscribed_systems: MapSet.new(state.initial_systems)
            }

            Logger.info("📡 Joined killmails channel",
              initial_systems: state.initial_systems,
              systems_count: length(state.initial_systems)
            )

            {:noreply, new_state}

          {:error, reason} ->
            Logger.error("❌ Failed to join channel: #{inspect(reason)}")
            # Retry connection after delay
            Process.send_after(self(), :connect, 5_000)
            {:noreply, state}
        end

      {:error, reason} ->
        Logger.error("❌ Failed to connect to WebSocket: #{inspect(reason)}")
        # Retry connection after delay
        Process.send_after(self(), :connect, 5_000)
        {:noreply, state}
    end
  end

  @impl true
  def handle_cast({:subscribe_systems, system_ids}, %{connected: true} = state) do
    case push_to_channel(state.channel, "subscribe_systems", %{systems: system_ids}) do
      :ok ->
        new_subscriptions = MapSet.union(state.subscribed_systems, MapSet.new(system_ids))
        new_state = %{state | subscribed_systems: new_subscriptions}

        Logger.info("✅ Subscribed to additional systems",
          systems: system_ids,
          total_subscriptions: MapSet.size(new_subscriptions)
        )

        {:noreply, new_state}

      {:error, reason} ->
        Logger.error("❌ Failed to subscribe to systems: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  def handle_cast({:subscribe_systems, _system_ids}, state) do
    Logger.warning("⚠️  Cannot subscribe: not connected to WebSocket")
    {:noreply, state}
  end

  @impl true
  def handle_cast({:unsubscribe_systems, system_ids}, %{connected: true} = state) do
    case push_to_channel(state.channel, "unsubscribe_systems", %{systems: system_ids}) do
      :ok ->
        new_subscriptions = MapSet.difference(state.subscribed_systems, MapSet.new(system_ids))
        new_state = %{state | subscribed_systems: new_subscriptions}

        Logger.info("❌ Unsubscribed from systems",
          systems: system_ids,
          remaining_subscriptions: MapSet.size(new_subscriptions)
        )

        {:noreply, new_state}

      {:error, reason} ->
        Logger.error("❌ Failed to unsubscribe from systems: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  def handle_cast({:unsubscribe_systems, _system_ids}, state) do
    Logger.warning("⚠️  Cannot unsubscribe: not connected to WebSocket")
    {:noreply, state}
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    status = %{
      connected: state.connected,
      server_url: state.server_url,
      subscription_id: state.subscription_id,
      subscribed_systems: MapSet.to_list(state.subscribed_systems),
      systems_count: MapSet.size(state.subscribed_systems)
    }

    Logger.info("📋 Current status", status)
    {:reply, {:ok, status}, state}
  end

  @impl true
  def handle_call(_msg, _from, state) do
    {:reply, {:error, :unknown_call}, state}
  end

  # Phoenix GenSocketClient Callbacks

  @impl GenSocketClient
  def handle_connected(transport, state) do
    Logger.debug("🔗 WebSocket transport connected", transport: inspect(transport))
    {:ok, state}
  end

  @impl GenSocketClient
  def handle_disconnected(reason, state) do
    Logger.warning("📡 WebSocket disconnected", reason: inspect(reason))

    # Update state and attempt reconnection
    new_state = %{state | connected: false, socket: nil, channel: nil}

    # Schedule reconnection
    Process.send_after(self(), :connect, 5_000)

    {:ok, new_state}
  end

  @impl GenSocketClient
  def handle_channel_closed(topic, payload, _transport, state) do
    Logger.warning("📺 Channel closed", topic: topic, payload: inspect(payload))

    # Update state
    new_state = %{state | channel: nil, connected: false}

    # Attempt to rejoin
    Process.send_after(self(), :connect, 2_000)

    {:ok, new_state}
  end

  @impl GenSocketClient
  def handle_message(topic, event, payload, _transport, state) do
    handle_channel_message(topic, event, payload, state)
  end

  @impl GenSocketClient
  def handle_reply(topic, ref, payload, _transport, state) do
    Logger.debug("📬 Channel reply",
      topic: topic,
      ref: ref,
      status: get_in(payload, ["status"])
    )

    # Handle join reply to extract subscription_id
    if topic == "killmails:lobby" and get_in(payload, ["status"]) == "ok" do
      subscription_id = get_in(payload, ["response", "subscription_id"])
      new_state = %{state | subscription_id: subscription_id}
      {:ok, new_state}
    else
      {:ok, state}
    end
  end

  # Private Helper Functions

  defp connect_to_websocket(state) do
    url = "#{state.server_url}/socket/websocket"

    socket_opts = [
      url: url,
      params: %{vsn: "2.0.0"}
    ]

    case GenSocketClient.start_link(__MODULE__, nil, socket_opts) do
      {:ok, socket} -> {:ok, socket}
      error -> error
    end
  end

  defp join_channel(socket, initial_systems) do
    join_params = if Enum.empty?(initial_systems) do
      %{}
    else
      %{systems: initial_systems}
    end

    case GenSocketClient.join(socket, "killmails:lobby", join_params) do
      {:ok, response} ->
        Logger.debug("📺 Joined channel", response: inspect(response))
        {:ok, socket}
      error -> error
    end
  end

  defp push_to_channel(socket, event, payload) when is_pid(socket) do
    case GenSocketClient.push(socket, "killmails:lobby", event, payload) do
      {:ok, _ref} -> :ok
      error -> error
    end
  end

  defp push_to_channel(_socket, _event, _payload) do
    {:error, :no_socket}
  end

  defp handle_channel_message("killmails:lobby", "killmail_update", payload, state) do
    system_id = payload["system_id"]
    killmails = payload["killmails"] || []
    timestamp = payload["timestamp"]
    is_preload = payload["preload"] || false

    if is_preload do
      Logger.info("📦 Preloaded killmails for system #{system_id}:",
        killmails_count: length(killmails),
        timestamp: timestamp,
        preload: true
      )
    else
      Logger.info("🔥 New real-time killmails in system #{system_id}:",
        killmails_count: length(killmails),
        timestamp: timestamp,
        preload: false
      )
    end

    # Process each killmail
    Enum.with_index(killmails, 1)
    |> Enum.each(fn {killmail, index} ->
      killmail_id = killmail["killmail_id"]
      victim = killmail["victim"] || %{}
      attackers = killmail["attackers"] || []

      character_name = victim["character_name"] || "Unknown"
      ship_name = victim["ship_type_name"] || "Unknown ship"
      kill_time = killmail["kill_time"] || killmail["killmail_time"] || "Unknown time"

      prefix = if is_preload, do: "📦", else: "🔥"

      Logger.info("   #{prefix} [#{index}] Killmail ID: #{killmail_id}",
        victim: character_name,
        ship: ship_name,
        kill_time: kill_time,
        attackers_count: length(attackers)
      )
    end)

    # You can add custom handling here:
    # - Store killmails in database
    # - Forward to other processes
    # - Trigger business logic
    # - Send notifications

    {:ok, state}
  end

  defp handle_channel_message("killmails:lobby", "kill_count_update", payload, state) do
    system_id = payload["system_id"]
    count = payload["count"]

    Logger.info("📊 Kill count update for system #{system_id}: #{count} kills")

    {:ok, state}
  end

  defp handle_channel_message(topic, event, payload, state) do
    Logger.debug("📨 Unhandled channel message",
      topic: topic,
      event: event,
      payload: inspect(payload)
    )

    {:ok, state}
  end
end

# Example usage module
defmodule WandererKills.WebSocketClient.Example do
  @moduledoc """
  Example usage of the WandererKills WebSocket client.

  Run this example with:

      iex> WandererKills.WebSocketClient.Example.run()
  """

  require Logger

  @doc """
  Run the WebSocket client example.
  """
  def run do
    Logger.info("🚀 Starting WandererKills WebSocket client example...")
    Logger.info("📋 This example demonstrates:")
    Logger.info("   1. Connecting with initial systems (Jita, Amarr)")
    Logger.info("   2. Receiving preloaded killmails for those systems")
    Logger.info("   3. Subscribing to additional systems (Dodixie)")
    Logger.info("   4. Receiving real-time killmail updates")

    # Start the client with some popular systems
    initial_systems = [30000142, 30002187]  # Jita, Amarr
    client_opts = [
      server_url: "ws://localhost:4004",
      systems: initial_systems,
      name: :wanderer_websocket_client
    ]

    Logger.info("🔌 Connecting to WebSocket with initial systems:",
      systems: initial_systems,
      system_names: ["Jita (30000142)", "Amarr (30002187)"]
    )

    case WandererKills.WebSocketClient.start_link(client_opts) do
      {:ok, pid} ->
        Logger.info("✅ WebSocket client started successfully")
        Logger.info("⏳ Watch for preloaded killmails to arrive shortly...")

        # Wait a bit for connection to establish and preload to complete
        Process.sleep(3_000)

        # Subscribe to additional systems after 5 seconds
        spawn(fn ->
          Process.sleep(5_000)
          Logger.info("📡 Adding Dodixie to subscriptions...")
          Logger.info("⏳ Watch for preloaded killmails from Dodixie...")
          WandererKills.WebSocketClient.subscribe_to_systems(pid, [30002659]) # Dodixie
        end)

        # Unsubscribe from Jita after 15 seconds
        spawn(fn ->
          Process.sleep(15_000)
          Logger.info("❌ Removing Jita from subscriptions...")
          WandererKills.WebSocketClient.unsubscribe_from_systems(pid, [30000142]) # Jita
        end)

        # Get status after 20 seconds
        spawn(fn ->
          Process.sleep(20_000)
          case WandererKills.WebSocketClient.get_status(pid) do
            {:ok, status} ->
              Logger.info("📋 Current client status:",
                connected: status.connected,
                systems_count: status.systems_count,
                subscribed_systems: status.subscribed_systems
              )
            {:error, reason} ->
              Logger.error("❌ Failed to get status: #{inspect(reason)}")
          end
        end)

        # Keep the example running
        Logger.info("")
        Logger.info("🎧 Client is now listening for killmail updates...")
        Logger.info("💡 You can interact with it using:")
        Logger.info("   WandererKills.WebSocketClient.subscribe_to_systems(:wanderer_websocket_client, [system_ids])")
        Logger.info("   WandererKills.WebSocketClient.unsubscribe_from_systems(:wanderer_websocket_client, [system_ids])")
        Logger.info("   WandererKills.WebSocketClient.get_status(:wanderer_websocket_client)")
        Logger.info("   WandererKills.WebSocketClient.stop(:wanderer_websocket_client)")
        Logger.info("")
        Logger.info("📦 Preloaded killmails have a 📦 icon")
        Logger.info("🔥 Real-time killmails have a 🔥 icon")

        {:ok, pid}

      {:error, reason} ->
        Logger.error("❌ Failed to start WebSocket client: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Stop the example client.
  """
  def stop do
    case Process.whereis(:wanderer_websocket_client) do
      nil ->
        Logger.info("ℹ️  WebSocket client is not running")
        :ok

      pid ->
        WandererKills.WebSocketClient.stop(pid)
        Logger.info("🛑 WebSocket client stopped")
        :ok
    end
  end

  @doc """
  Simple example that connects with initial systems and shows preload behavior.

  This demonstrates the most common use case: connecting to a few systems
  and immediately receiving cached killmail data.
  """
  def simple_example do
    Logger.info("🚀 Simple WebSocket client example")
    Logger.info("📋 Connecting to Jita and Amarr with preload...")

    # Connect with initial systems
    {:ok, pid} = WandererKills.WebSocketClient.start_link([
      server_url: "ws://localhost:4004",
      systems: [30000142, 30002187],  # Jita, Amarr
      name: :simple_client
    ])

    Logger.info("✅ Connected! Watch for preloaded killmails...")

    # Wait and show status
    Process.sleep(5_000)

    case WandererKills.WebSocketClient.get_status(pid) do
      {:ok, status} ->
        Logger.info("📋 Client status: #{status.systems_count} systems, connected: #{status.connected}")
      {:error, _} ->
        Logger.warning("⚠️  Could not get client status")
    end

    Logger.info("🎧 Listening for real-time updates... (Ctrl+C to stop)")

    # Keep running until stopped
    Process.sleep(:infinity)
  end
end
