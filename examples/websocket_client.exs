defmodule WandererKills.WebSocketClient do
  @moduledoc """
  Elixir WebSocket client for WandererKills real-time killmail subscriptions.

  This example shows how to connect to the WandererKills WebSocket API
  from within Elixir to receive real-time killmail updates for:
  - Specific EVE Online systems
  - Specific characters (as victim or attacker)

  Features:
  - System-based subscriptions: Monitor specific solar systems
  - Character-based subscriptions: Track when specific characters get kills or die
  - Mixed subscriptions: Combine both system and character filters (OR logic)
  - Real-time updates: Receive killmails as they happen
  - Historical preload: Get recent kills when first subscribing
  - Extended preload: Request historical data with progressive delivery

  ## Usage

      # Start the client
      {:ok, pid} = WandererKills.WebSocketClient.start_link([
        server_url: "ws://localhost:4004",
        systems: [30000142, 30002187],      # Jita, Amarr
        character_ids: [95465499],          # Optional: track characters
        preload: %{                         # Optional: extended preload
          enabled: true,
          limit_per_system: 50,
          since_hours: 72
        },
        client_identifier: "my_app"         # Optional: helps identify your connection
      ])

      # Subscribe to additional systems
      WandererKills.WebSocketClient.subscribe_to_systems(pid, [30002659]) # Dodixie

      # Subscribe to characters
      WandererKills.WebSocketClient.subscribe_to_characters(pid, [12345678])

      # Unsubscribe from systems
      WandererKills.WebSocketClient.unsubscribe_from_systems(pid, [30000142])

      # Unsubscribe from characters
      WandererKills.WebSocketClient.unsubscribe_from_characters(pid, [95465499])

      # Get current status
      WandererKills.WebSocketClient.get_status(pid)

      # Stop the client
      WandererKills.WebSocketClient.stop(pid)

  ## Dependencies

  This example uses `phoenix_client` for WebSocket communication:

      Mix.install([
        {:phoenix_client, "~> 0.3"},
        {:websocket_client, "~> 1.5"},
        {:jason, "~> 1.4"}
      ])
  """

  use GenServer
  require Logger

  # Client API

  @doc """
  Start the WebSocket client.

  ## Options

    * `:server_url` - WebSocket server URL (required)
    * `:systems` - Initial systems to subscribe to (optional)
    * `:character_ids` - Initial characters to track (optional)
    * `:preload` - Extended preload configuration (optional)
    * `:client_identifier` - Client identifier for debugging (optional, max 32 chars)
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
  @spec subscribe_to_systems(pid() | atom(), [integer()]) :: :ok | {:error, term()}
  def subscribe_to_systems(client, system_ids) when is_list(system_ids) do
    GenServer.call(client, {:subscribe_systems, system_ids})
  end

  @doc """
  Unsubscribe from EVE Online systems.
  """
  @spec unsubscribe_from_systems(pid() | atom(), [integer()]) :: :ok | {:error, term()}
  def unsubscribe_from_systems(client, system_ids) when is_list(system_ids) do
    GenServer.call(client, {:unsubscribe_systems, system_ids})
  end

  @doc """
  Subscribe to specific characters (track as victim or attacker).
  """
  @spec subscribe_to_characters(pid() | atom(), [integer()]) :: :ok | {:error, term()}
  def subscribe_to_characters(client, character_ids) when is_list(character_ids) do
    GenServer.call(client, {:subscribe_characters, character_ids})
  end

  @doc """
  Unsubscribe from specific characters.
  """
  @spec unsubscribe_from_characters(pid() | atom(), [integer()]) :: :ok | {:error, term()}
  def unsubscribe_from_characters(client, character_ids) when is_list(character_ids) do
    GenServer.call(client, {:unsubscribe_characters, character_ids})
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
    initial_characters = Keyword.get(opts, :character_ids, [])
    preload = Keyword.get(opts, :preload, %{})
    client_identifier = Keyword.get(opts, :client_identifier, nil)

    # Convert HTTP URL to WebSocket URL if needed
    websocket_url =
      server_url
      |> String.replace("http://", "ws://")
      |> String.replace("https://", "wss://")

    state = %{
      server_url: websocket_url,
      socket: nil,
      channel: nil,
      channel_ref: nil,
      subscribed_systems: MapSet.new(),
      subscribed_characters: MapSet.new(),
      initial_systems: initial_systems,
      initial_characters: initial_characters,
      preload: preload,
      subscription_id: nil,
      connected: false,
      client_identifier: client_identifier
    }

    Logger.info("🚀 Starting WandererKills WebSocket client",
      server_url: websocket_url,
      initial_systems: initial_systems,
      initial_characters: initial_characters,
      client_identifier: client_identifier
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
        channel_params = %{}
        channel_params = if length(state.initial_systems) > 0,
          do: Map.put(channel_params, "systems", state.initial_systems),
          else: channel_params
        
        channel_params = if length(state.initial_characters) > 0,
          do: Map.put(channel_params, "character_ids", state.initial_characters),
          else: channel_params
          
        channel_params = if map_size(state.preload) > 0,
          do: Map.put(channel_params, "preload", state.preload),
          else: channel_params

        case PhoenixClient.Channel.join(socket, "killmails:lobby", channel_params) do
          {:ok, response, channel_ref} ->
            subscription_id = Map.get(response, "subscription_id")
            
            new_state = %{state |
              socket: socket,
              channel: socket,
              channel_ref: channel_ref,
              connected: true,
              subscription_id: subscription_id,
              subscribed_systems: MapSet.new(state.initial_systems),
              subscribed_characters: MapSet.new(state.initial_characters)
            }

            Logger.info("📡 Joined killmails channel",
              subscription_id: subscription_id,
              initial_systems: state.initial_systems,
              initial_characters: state.initial_characters,
              systems_count: length(state.initial_systems),
              characters_count: length(state.initial_characters)
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
  def handle_info(%{"event" => "killmail_update", "payload" => payload}, state) do
    system_id = payload["system_id"]
    killmails = payload["killmails"] || []
    timestamp = payload["timestamp"]
    is_preload = payload["preload"] || false

    Logger.info("🔥 New killmails in system #{system_id}:",
      killmails_count: length(killmails),
      timestamp: timestamp,
      preload: is_preload and "Yes (historical data)" || "No (real-time)"
    )

    # Process first few killmails
    Enum.take(killmails, 3)
    |> Enum.with_index(1)
    |> Enum.each(fn {killmail, index} ->
      killmail_id = killmail["killmail_id"]
      victim = killmail["victim"] || %{}
      attackers = killmail["attackers"] || []
      zkb = killmail["zkb"] || %{}

      victim_name = victim["character_name"] || "Unknown"
      ship_name = victim["ship_name"] || "Unknown ship"
      corp_name = victim["corporation_name"] || "Unknown"
      
      Logger.info("   [#{index}] Killmail ID: #{killmail_id}")
      Logger.info("       Victim: #{victim_name} (#{ship_name})")
      Logger.info("       Corporation: #{corp_name}")
      
      if length(attackers) > 0 do
        Logger.info("       Attackers: #{length(attackers)}")
        
        final_blow = Enum.find(attackers, fn a -> a["final_blow"] == true end)
        if final_blow do
          attacker_name = final_blow["character_name"] || "Unknown"
          attacker_ship = final_blow["ship_name"] || "Unknown ship"
          Logger.info("       Final blow: #{attacker_name} (#{attacker_ship})")
        end
      end
      
      if zkb["total_value"] do
        value_m = zkb["total_value"] / 1_000_000
        Logger.info("       Value: #{Float.round(value_m, 2)}M ISK")
      end
    end)

    # You can add custom handling here:
    # - Store killmails in database
    # - Forward to other processes
    # - Trigger business logic
    # - Send notifications

    {:noreply, state}
  end

  @impl true
  def handle_info(%{"event" => "kill_count_update", "payload" => payload}, state) do
    system_id = payload["system_id"]
    count = payload["count"]

    Logger.info("📊 Kill count update for system #{system_id}: #{count} kills")

    {:noreply, state}
  end

  @impl true
  def handle_info(%{"event" => "preload_status", "payload" => payload}, state) do
    Logger.info("⏳ Preload progress: #{payload["status"]}")
    Logger.info("   Current system: #{payload["current_system"] || "N/A"}")
    Logger.info("   Systems complete: #{payload["systems_complete"]}/#{payload["total_systems"]}")

    {:noreply, state}
  end

  @impl true
  def handle_info(%{"event" => "preload_batch", "payload" => payload}, state) do
    kills = payload["kills"] || []
    Logger.info("📦 Received preload batch: #{length(kills)} historical kills")
    
    Enum.take(kills, 3)
    |> Enum.each(fn kill ->
      Logger.info("   Historical kill #{kill["killmail_id"]} from #{kill["kill_time"]}")
    end)

    {:noreply, state}
  end

  @impl true
  def handle_info(%{"event" => "preload_complete", "payload" => payload}, state) do
    Logger.info("✅ Preload complete!")
    Logger.info("   Total kills loaded: #{payload["total_kills"]}")
    Logger.info("   Systems processed: #{payload["systems_processed"]}")
    
    errors = payload["errors"] || []
    if length(errors) > 0 do
      Logger.info("   ⚠️ Errors encountered: #{length(errors)}")
      Enum.each(errors, fn err ->
        Logger.info("      - #{err}")
      end)
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(%{"event" => "phx_close"}, state) do
    Logger.warning("📡 Channel closed by server")
    new_state = %{state | connected: false, socket: nil, channel: nil}
    Process.send_after(self(), :connect, 5_000)
    {:noreply, new_state}
  end

  @impl true
  def handle_info(%{"event" => "phx_error", "payload" => payload}, state) do
    Logger.error("❌ Channel error: #{inspect(payload)}")
    {:noreply, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("📨 Unhandled message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def handle_call({:subscribe_systems, system_ids}, _from, %{connected: true} = state) do
    case PhoenixClient.Channel.push(state.socket, state.channel_ref, "subscribe_systems", %{"systems" => system_ids}) do
      {:ok, response} ->
        subscribed_systems = response["subscribed_systems"] || []
        new_state = %{state | subscribed_systems: MapSet.new(subscribed_systems)}
        
        Logger.info("✅ Subscribed to systems: #{Enum.join(system_ids, ", ")}")
        Logger.info("📡 Total system subscriptions: #{length(subscribed_systems)}")
        
        {:reply, :ok, new_state}

      {:error, reason} ->
        Logger.error("❌ Failed to subscribe to systems: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:subscribe_systems, _}, _from, state) do
    {:reply, {:error, :not_connected}, state}
  end

  @impl true
  def handle_call({:unsubscribe_systems, system_ids}, _from, %{connected: true} = state) do
    case PhoenixClient.Channel.push(state.socket, state.channel_ref, "unsubscribe_systems", %{"systems" => system_ids}) do
      {:ok, response} ->
        subscribed_systems = response["subscribed_systems"] || []
        new_state = %{state | subscribed_systems: MapSet.new(subscribed_systems)}
        
        Logger.info("❌ Unsubscribed from systems: #{Enum.join(system_ids, ", ")}")
        Logger.info("📡 Remaining system subscriptions: #{length(subscribed_systems)}")
        
        {:reply, :ok, new_state}

      {:error, reason} ->
        Logger.error("❌ Failed to unsubscribe from systems: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:unsubscribe_systems, _}, _from, state) do
    {:reply, {:error, :not_connected}, state}
  end

  @impl true
  def handle_call({:subscribe_characters, character_ids}, _from, %{connected: true} = state) do
    case PhoenixClient.Channel.push(state.socket, state.channel_ref, "subscribe_characters", %{"character_ids" => character_ids}) do
      {:ok, response} ->
        subscribed_characters = response["subscribed_characters"] || []
        new_state = %{state | subscribed_characters: MapSet.new(subscribed_characters)}
        
        Logger.info("✅ Subscribed to characters: #{Enum.join(character_ids, ", ")}")
        Logger.info("👤 Total character subscriptions: #{length(subscribed_characters)}")
        
        {:reply, :ok, new_state}

      {:error, reason} ->
        Logger.error("❌ Failed to subscribe to characters: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:subscribe_characters, _}, _from, state) do
    {:reply, {:error, :not_connected}, state}
  end

  @impl true
  def handle_call({:unsubscribe_characters, character_ids}, _from, %{connected: true} = state) do
    case PhoenixClient.Channel.push(state.socket, state.channel_ref, "unsubscribe_characters", %{"character_ids" => character_ids}) do
      {:ok, response} ->
        subscribed_characters = response["subscribed_characters"] || []
        new_state = %{state | subscribed_characters: MapSet.new(subscribed_characters)}
        
        Logger.info("❌ Unsubscribed from characters: #{Enum.join(character_ids, ", ")}")
        Logger.info("👤 Remaining character subscriptions: #{length(subscribed_characters)}")
        
        {:reply, :ok, new_state}

      {:error, reason} ->
        Logger.error("❌ Failed to unsubscribe from characters: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:unsubscribe_characters, _}, _from, state) do
    {:reply, {:error, :not_connected}, state}
  end

  @impl true
  def handle_call(:get_status, _from, %{connected: true} = state) do
    case PhoenixClient.Channel.push(state.socket, state.channel_ref, "get_status", %{}) do
      {:ok, response} ->
        status = %{
          connected: state.connected,
          server_url: state.server_url,
          subscription_id: response["subscription_id"] || state.subscription_id,
          subscribed_systems: response["subscribed_systems"] || MapSet.to_list(state.subscribed_systems),
          subscribed_characters: response["subscribed_characters"] || MapSet.to_list(state.subscribed_characters),
          systems_count: length(response["subscribed_systems"] || []),
          characters_count: length(response["subscribed_characters"] || [])
        }
        
        Logger.info("📋 Current status: #{status.systems_count} systems, #{status.characters_count} characters")
        {:reply, {:ok, status}, state}

      {:error, reason} ->
        Logger.error("❌ Failed to get status: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:get_status, _from, state) do
    status = %{
      connected: false,
      server_url: state.server_url,
      subscription_id: nil,
      subscribed_systems: [],
      subscribed_characters: [],
      systems_count: 0,
      characters_count: 0
    }
    {:reply, {:ok, status}, state}
  end

  @impl true
  def handle_call(_msg, _from, state) do
    {:reply, {:error, :unknown_call}, state}
  end

  # Private Helper Functions

  defp connect_to_websocket(state) do
    params = %{}
    params = if state.client_identifier do
      Map.put(params, "client_identifier", state.client_identifier)
    else
      params
    end

    PhoenixClient.Socket.start_link(
      url: "#{state.server_url}/socket",
      params: params,
      reconnect_interval: 5_000
    )
  end
end

# Example usage module
defmodule WandererKills.WebSocketClient.Example do
  @moduledoc """
  Example usage of the WandererKills WebSocket client.

  Run these examples with:

      # Basic example
      iex> WandererKills.WebSocketClient.Example.basic_example()
      
      # Extended preload example
      iex> WandererKills.WebSocketClient.Example.preload_example()
      
      # Advanced example with dynamic subscriptions
      iex> WandererKills.WebSocketClient.Example.advanced_example()
  """

  require Logger

  @doc """
  Basic example showing simple connection and subscription.
  """
  def basic_example do
    Logger.info("🚀 Basic WebSocket client example")
    Logger.info("📋 Connecting to popular systems...")

    # Start the client
    {:ok, pid} = WandererKills.WebSocketClient.start_link([
      server_url: "ws://localhost:4004",
      systems: [30000142, 30002659, 30002187],  # Jita, Dodixie, Amarr
      character_ids: [95465499, 90379338],       # Example character IDs
      client_identifier: "basic_example"
    ])

    Logger.info("✅ Connected! Watching for killmail updates...")

    # Wait a bit, then get status
    Process.sleep(5_000)
    
    case WandererKills.WebSocketClient.get_status(pid) do
      {:ok, status} ->
        Logger.info("📋 Current status:")
        Logger.info("   Subscription ID: #{status.subscription_id}")
        Logger.info("   Subscribed systems: #{length(status.subscribed_systems)}")
        Logger.info("   Subscribed characters: #{length(status.subscribed_characters)}")
      {:error, reason} ->
        Logger.error("Failed to get status: #{inspect(reason)}")
    end

    # Keep running for 5 minutes
    Logger.info("🎧 Listening for killmail updates for 5 minutes...")
    Process.sleep(5 * 60 * 1000)

    WandererKills.WebSocketClient.stop(pid)
    Logger.info("🛑 Example completed")
  end

  @doc """
  Example with extended historical data preload.
  """
  def preload_example do
    Logger.info("🚀 Extended preload example")
    Logger.info("📋 Connecting with historical data request...")

    # Start with extended preload configuration
    {:ok, pid} = WandererKills.WebSocketClient.start_link([
      server_url: "ws://localhost:4004",
      systems: [30000142, 30002187],      # Jita and Amarr
      character_ids: [95465499],          # Track specific character
      preload: %{
        enabled: true,
        limit_per_system: 50,             # Get up to 50 kills per system
        since_hours: 72,                  # Look back 3 days
        delivery_batch_size: 10,          # Deliver in batches of 10
        delivery_interval_ms: 500         # 500ms between batches
      },
      client_identifier: "preload_example"
    ])

    Logger.info("🚀 Connected with extended preload configuration")
    Logger.info("⏳ Watch for historical data to arrive in batches...")

    # Keep running for 10 minutes to see real-time kills after preload
    Process.sleep(10 * 60 * 1000)

    WandererKills.WebSocketClient.stop(pid)
    Logger.info("🛑 Example completed")
  end

  @doc """
  Advanced example showing dynamic subscription management.
  """
  def advanced_example do
    Logger.info("🚀 Advanced WebSocket client example")
    Logger.info("📋 This example demonstrates dynamic subscription management")

    # Start with initial subscriptions
    {:ok, pid} = WandererKills.WebSocketClient.start_link([
      server_url: "ws://localhost:4004",
      systems: [30000142, 30002187],          # Jita, Amarr
      character_ids: [95465499, 90379338],    # Example character IDs
      client_identifier: "advanced_example",
      name: :advanced_client
    ])

    Logger.info("✅ Connected with mixed subscriptions")
    Logger.info("   The client will now receive killmails from:")
    Logger.info("   1. Jita system (30000142)")
    Logger.info("   2. Amarr system (30002187)")
    Logger.info("   3. Any system where character 95465499 gets a kill or dies")
    Logger.info("   4. Any system where character 90379338 gets a kill or dies")

    # Wait 30 seconds, then add more subscriptions
    Process.sleep(30_000)
    Logger.info("\n📝 Adding more subscriptions...")

    # Add more systems
    WandererKills.WebSocketClient.subscribe_to_systems(pid, [30002659])  # Dodixie
    
    # Add more characters
    WandererKills.WebSocketClient.subscribe_to_characters(pid, [12345678])
    
    # Get updated status
    {:ok, status} = WandererKills.WebSocketClient.get_status(pid)
    Logger.info("📋 Updated subscriptions: #{status.systems_count} systems, #{status.characters_count} characters")

    # Wait another 30 seconds, then remove some subscriptions
    Process.sleep(30_000)
    Logger.info("\n📝 Removing some subscriptions...")

    # Remove a system
    WandererKills.WebSocketClient.unsubscribe_from_systems(pid, [30000142])  # Remove Jita
    
    # Remove a character
    WandererKills.WebSocketClient.unsubscribe_from_characters(pid, [90379338])
    
    # Get final status
    {:ok, final_status} = WandererKills.WebSocketClient.get_status(pid)
    Logger.info("📋 Final subscriptions: #{final_status.systems_count} systems, #{final_status.characters_count} characters")

    # Keep running for remaining time
    Process.sleep(4 * 60 * 1000)

    WandererKills.WebSocketClient.stop(pid)
    Logger.info("🛑 Example completed")
  end

  @doc """
  Interactive example that starts a client you can control from IEx.
  """
  def interactive do
    Logger.info("🚀 Starting interactive WebSocket client...")
    Logger.info("📋 This client will be registered as :wanderer_client")

    # Start with some initial systems
    {:ok, _pid} = WandererKills.WebSocketClient.start_link([
      server_url: "ws://localhost:4004",
      systems: [30000142],  # Start with just Jita
      client_identifier: "interactive_client",
      name: :wanderer_client
    ])

    Logger.info("✅ Client started! You can now interact with it:")
    Logger.info("")
    Logger.info("   # Subscribe to systems")
    Logger.info("   WandererKills.WebSocketClient.subscribe_to_systems(:wanderer_client, [30002659, 30002187])")
    Logger.info("")
    Logger.info("   # Subscribe to characters")
    Logger.info("   WandererKills.WebSocketClient.subscribe_to_characters(:wanderer_client, [95465499])")
    Logger.info("")
    Logger.info("   # Unsubscribe from systems")
    Logger.info("   WandererKills.WebSocketClient.unsubscribe_from_systems(:wanderer_client, [30000142])")
    Logger.info("")
    Logger.info("   # Get current status")
    Logger.info("   WandererKills.WebSocketClient.get_status(:wanderer_client)")
    Logger.info("")
    Logger.info("   # Stop the client")
    Logger.info("   WandererKills.WebSocketClient.stop(:wanderer_client)")
    Logger.info("")

    :ok
  end
end

# Installation script for dependencies when running as a script
if Code.ensure_loaded?(Mix) do
  Logger.info("📦 Installing dependencies...")
  Mix.install([
    {:phoenix_client, "~> 0.3"},
    {:websocket_client, "~> 1.5"},
    {:jason, "~> 1.4"}
  ])
end