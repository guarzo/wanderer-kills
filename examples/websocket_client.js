/**
 * WandererKills WebSocket Client Example
 * 
 * This example shows how to connect to the WandererKills WebSocket API
 * to receive real-time killmail updates for:
 * - Specific EVE Online systems
 * - Specific characters (as victim or attacker)
 * 
 * Features:
 * - System-based subscriptions: Monitor specific solar systems
 * - Character-based subscriptions: Track when specific characters get kills or die
 * - Mixed subscriptions: Combine both system and character filters (OR logic)
 * - Real-time updates: Receive killmails as they happen
 * - Historical preload: Get recent kills when first subscribing
 * - Extended preload: Request up to 1 week of historical data with progressive delivery
 *
 * Extended Preload Configuration:
 * When connecting, you can request extended historical data by providing a preload config:
 * {
 *   enabled: true,              // Enable extended preload (default: true)
 *   limit_per_system: 100,      // Max kills per system (default: 100, max: 200)
 *   since_hours: 168,           // Hours to look back (default: 168 = 1 week)
 *   delivery_batch_size: 10,    // Kills per batch (default: 10)
 *   delivery_interval_ms: 1000  // Delay between batches (default: 1000ms)
 * }
 *
 * The extended preload feature:
 * - Fetches historical data asynchronously with rate limiting
 * - Delivers kills progressively in batches to prevent overwhelming clients
 * - Sends status updates during the preload process
 * - Handles up to 200 kills per system going back 1 week
 *
 * Usage:
 * node websocket_client.js [basic|preload|advanced]
 */

// Import Phoenix Socket (you'll need to install phoenix)
// npm install phoenix
import { Socket } from 'phoenix';

class WandererKillsClient {
  constructor(serverUrl) {
    this.serverUrl = serverUrl;
    this.socket = null;
    this.channel = null;
    this.systemSubscriptions = new Set();
    this.characterSubscriptions = new Set();
  }

  /**
   * Connect to the WebSocket server
   * @param {Object|number} options - Connection options object or timeout number (deprecated)
   * @param {number[]} options.systems - System IDs to subscribe to
   * @param {number[]} options.characters - Character IDs to track
   * @param {Object} options.preload - Extended preload configuration
   * @param {number} options.timeout - Connection timeout in milliseconds (default: 10000)
   * @returns {Promise} Resolves when connected, rejects on error or timeout
   * 
   * @deprecated Passing a number directly as timeout is deprecated. Use options object instead.
   * @example
   * // New way (recommended)
   * await client.connect({ systems: [30000142], timeout: 5000 });
   * 
   * // Old way (deprecated but still supported)
   * await client.connect(5000);
   */
  async connect(options = {}) {
    // Backward compatibility: if options is a number, treat it as timeout
    if (typeof options === 'number') {
      console.warn('Deprecated: Passing timeout as a number is deprecated. Use an options object instead.');
      options = { timeout: options };
    }
    
    const {
      systems = [],
      characters = [],
      preload = null,
      timeout = 10000
    } = options;

    return new Promise((resolve, reject) => {
      // Set up a connection timeout
      const timeoutId = setTimeout(() => {
        this.disconnect();
        reject(new Error('Connection timeout'));
      }, timeout);

      // Create socket connection with optional client identifier
      this.socket = new Socket(`${this.serverUrl}/socket`, {
        timeout: timeout,
        params: {
          // Optional: provide a client identifier for easier debugging
          // This will be included in server logs to help identify your connection
          client_identifier: 'js_example_client'
        }
      });

      // Handle connection events
      this.socket.onError((error) => {
        console.error('Socket error:', error);
        clearTimeout(timeoutId);
        reject(error);
      });

      this.socket.onClose(() => {
        console.log('Socket connection closed');
      });

      // Connect to the socket
      this.socket.connect();

      // Build channel params
      const channelParams = {};
      if (systems.length > 0) channelParams.systems = systems;
      if (characters.length > 0) channelParams.characters = characters;
      if (preload) channelParams.preload = preload;

      // Join the killmails channel
      this.channel = this.socket.channel('killmails:lobby', channelParams);

      this.channel.join()
        .receive('ok', (response) => {
          clearTimeout(timeoutId);
          console.log('Connected to WandererKills WebSocket');
          console.log('Connection details:', response);

          // Track initial subscriptions
          if (systems.length > 0) {
            systems.forEach(id => this.systemSubscriptions.add(id));
          }
          if (characters.length > 0) {
            characters.forEach(id => this.characterSubscriptions.add(id));
          }

          this.setupEventHandlers();
          resolve(response);
        })
        .receive('error', (error) => {
          clearTimeout(timeoutId);
          console.error('Failed to join channel:', error);
          this.disconnect();
          reject(error);
        })
        .receive('timeout', () => {
          clearTimeout(timeoutId);
          console.error('Channel join timeout');
          this.disconnect();
          reject(new Error('Channel join timeout'));
        });
    });
  }

  /**
   * Set up event handlers for real-time data
   */
  setupEventHandlers() {
    // Listen for killmail updates
    this.channel.on('killmail_update', (payload) => {
      console.log(`🔥 New killmails in system ${payload.system_id}:`);
      console.log(`   Killmails: ${payload.killmails.length}`);
      console.log(`   Timestamp: ${payload.timestamp}`);
      console.log(`   Preload: ${payload.preload ? 'Yes (historical data)' : 'No (real-time)'}`);
      
      // Process each killmail
      payload.killmails.forEach((killmail, index) => {
        console.log(`   [${index + 1}] Killmail ID: ${killmail.killmail_id}`);
        if (killmail.victim) {
          console.log(`       Victim: ${killmail.victim.character_name || 'Unknown'} (${killmail.victim.ship_name || 'Unknown ship'})`);
          console.log(`       Corporation: ${killmail.victim.corporation_name || 'Unknown'}`);
        }
        if (killmail.attackers && killmail.attackers.length > 0) {
          console.log(`       Attackers: ${killmail.attackers.length}`);
          const finalBlow = killmail.attackers.find(a => a.final_blow);
          if (finalBlow) {
            console.log(`       Final blow: ${finalBlow.character_name || 'Unknown'} (${finalBlow.ship_name || 'Unknown ship'})`);
          }
        }
        if (killmail.zkb) {
          console.log(`       Value: ${(killmail.zkb.total_value / 1000000).toFixed(2)}M ISK`);
        }
      });
    });

    // Listen for kill count updates
    this.channel.on('kill_count_update', (payload) => {
      console.log(`📊 Kill count update for system ${payload.system_id}: ${payload.count} kills`);
    });

    // Extended preload events
    this.channel.on('preload_status', (payload) => {
      console.log(`⏳ Preload progress: ${payload.status}`);
      console.log(`   Current system: ${payload.current_system || 'N/A'}`);
      console.log(`   Systems complete: ${payload.systems_complete}/${payload.total_systems}`);
    });

    this.channel.on('preload_batch', (payload) => {
      console.log(`📦 Received preload batch: ${payload.kills.length} historical kills`);
      // Process historical kills - these come in the same format as regular kills
      payload.kills.forEach((kill) => {
        console.log(`   Historical kill ${kill.killmail_id} from ${kill.kill_time}`);
      });
    });

    this.channel.on('preload_complete', (payload) => {
      console.log(`✅ Preload complete!`);
      console.log(`   Total kills loaded: ${payload.total_kills}`);
      console.log(`   Systems processed: ${payload.systems_processed}`);
      if (payload.errors && payload.errors.length > 0) {
        console.log(`   ⚠️ Errors encountered: ${payload.errors.length}`);
        payload.errors.forEach(err => console.log(`      - ${err}`));
      }
    });
  }

  /**
   * Subscribe to specific systems
   * @param {number[]} systemIds - Array of EVE Online system IDs
   */
  async subscribeToSystems(systemIds) {
    return new Promise((resolve, reject) => {
      this.channel.push('subscribe_systems', { systems: systemIds })
        .receive('ok', (response) => {
          systemIds.forEach(id => this.systemSubscriptions.add(id));
          console.log(`✅ Subscribed to systems: ${systemIds.join(', ')}`);
          console.log(`📡 Total system subscriptions: ${response.subscribed_systems.length}`);
          resolve(response);
        })
        .receive('error', (error) => {
          console.error('Failed to subscribe to systems:', error);
          reject(error);
        });
    });
  }

  /**
   * Unsubscribe from specific systems
   * @param {number[]} systemIds - Array of EVE Online system IDs
   */
  async unsubscribeFromSystems(systemIds) {
    return new Promise((resolve, reject) => {
      this.channel.push('unsubscribe_systems', { systems: systemIds })
        .receive('ok', (response) => {
          systemIds.forEach(id => this.systemSubscriptions.delete(id));
          console.log(`❌ Unsubscribed from systems: ${systemIds.join(', ')}`);
          console.log(`📡 Remaining system subscriptions: ${response.subscribed_systems.length}`);
          resolve(response);
        })
        .receive('error', (error) => {
          console.error('Failed to unsubscribe from systems:', error);
          reject(error);
        });
    });
  }

  /**
   * Subscribe to specific characters (track as victim or attacker)
   * @param {number[]} characterIds - Array of EVE Online character IDs
   */
  async subscribeToCharacters(characterIds) {
    return new Promise((resolve, reject) => {
      this.channel.push('subscribe_characters', { characters: characterIds })
        .receive('ok', (response) => {
          console.log(`✅ Subscribed to characters: ${characterIds.join(', ')}`);
          console.log(`👤 Total character subscriptions: ${response.subscribed_characters.length}`);
          resolve(response);
        })
        .receive('error', (error) => {
          console.error('Failed to subscribe to characters:', error);
          reject(error);
        });
    });
  }

  /**
   * Unsubscribe from specific characters
   * @param {number[]} characterIds - Array of EVE Online character IDs
   */
  async unsubscribeFromCharacters(characterIds) {
    return new Promise((resolve, reject) => {
      this.channel.push('unsubscribe_characters', { characters: characterIds })
        .receive('ok', (response) => {
          console.log(`❌ Unsubscribed from characters: ${characterIds.join(', ')}`);
          console.log(`👤 Remaining character subscriptions: ${response.subscribed_characters.length}`);
          resolve(response);
        })
        .receive('error', (error) => {
          console.error('Failed to unsubscribe from characters:', error);
          reject(error);
        });
    });
  }

  /**
   * Get current subscription status
   */
  async getStatus() {
    return new Promise((resolve, reject) => {
      this.channel.push('get_status', {})
        .receive('ok', (response) => {
          console.log('📋 Current status:', response);
          console.log(`   Subscription ID: ${response.subscription_id}`);
          console.log(`   Subscribed systems: ${response.subscribed_systems.length}`);
          console.log(`   Subscribed characters: ${response.subscribed_characters.length}`);
          resolve(response);
        })
        .receive('error', (error) => {
          console.error('Failed to get status:', error);
          reject(error);
        });
    });
  }

  /**
   * Disconnect from the WebSocket server
   * @returns {Promise} Resolves when disconnected
   */
  async disconnect() {
    return new Promise((resolve) => {
      if (this.channel) {
        this.channel.leave()
          .receive('ok', () => {
            console.log('Left channel successfully');
            if (this.socket) {
              this.socket.disconnect(() => {
                console.log('Disconnected from WandererKills WebSocket');
                resolve();
              });
            } else {
              resolve();
            }
          })
          .receive('timeout', () => {
            console.warn('Channel leave timeout, forcing disconnect');
            if (this.socket) {
              this.socket.disconnect();
            }
            console.log('Disconnected from WandererKills WebSocket');
            resolve();
          });
      } else if (this.socket) {
        this.socket.disconnect(() => {
          console.log('Disconnected from WandererKills WebSocket');
          resolve();
        });
      } else {
        resolve();
      }
    });
  }
}

// Example usage - Basic connection
async function basicExample() {
  const client = new WandererKillsClient('ws://localhost:4004');

  try {
    // Connect to the server without preload
    await client.connect();

    // Subscribe to some popular systems
    // Jita (30000142), Dodixie (30002659), Amarr (30002187)
    await client.subscribeToSystems([30000142, 30002659, 30002187]);

    // Subscribe to specific characters (example character IDs)
    // These will track kills where these characters appear as victim or attacker
    await client.subscribeToCharacters([95465499, 90379338]);

    // Get current status
    await client.getStatus();

    // Keep connection alive for 5 minutes
    setTimeout(async () => {
      console.log('\n📍 Disconnecting...');
      await client.disconnect();
      process.exit(0);
    }, 5 * 60 * 1000);

  } catch (error) {
    console.error('Client error:', error);
    await client.disconnect();
    process.exit(1);
  }
}

// Example with extended historical data preload
async function extendedPreloadExample() {
  const client = new WandererKillsClient('ws://localhost:4004');
  let historicalKills = [];
  let realtimeKills = [];

  try {
    // Connect with initial systems and extended preload configuration
    await client.connect({
      systems: [30000142, 30002187], // Jita and Amarr
      characters: [95465499],         // Track specific character
      preload: {
        enabled: true,
        limit_per_system: 50,     // Get up to 50 kills per system
        since_hours: 72,          // Look back 3 days
        delivery_batch_size: 10,  // Deliver in batches of 10
        delivery_interval_ms: 500 // 500ms between batches
      }
    });

    console.log('🚀 Connected with extended preload configuration');

    // Override handlers to collect historical vs realtime kills
    client.channel.on('preload_batch', (payload) => {
      console.log(`📦 Received ${payload.kills.length} historical kills`);
      historicalKills = historicalKills.concat(payload.kills);
    });

    client.channel.on('killmail_update', (payload) => {
      if (!payload.preload) {
        console.log(`🔥 ${payload.killmails.length} new real-time kills!`);
        realtimeKills = realtimeKills.concat(payload.killmails);
      }
    });

    client.channel.on('preload_complete', (result) => {
      console.log('\n📊 Historical Data Summary:');
      console.log(`   Total historical kills: ${historicalKills.length}`);
      console.log(`   Systems processed: ${result.systems_processed}`);

      // Analyze historical data
      const totalValue = historicalKills.reduce((sum, kill) =>
        sum + (kill.zkb?.total_value || 0), 0
      );
      console.log(`   Total ISK destroyed: ${(totalValue / 1000000000).toFixed(2)}B ISK`);

      // Find most expensive kill
      const mostExpensive = historicalKills.reduce((max, kill) =>
        (kill.zkb?.total_value || 0) > (max.zkb?.total_value || 0) ? kill : max
      , historicalKills[0]);

      if (mostExpensive) {
        console.log(`   Most expensive kill: ${mostExpensive.killmail_id} - ${(mostExpensive.zkb.total_value / 1000000000).toFixed(2)}B ISK`);
      }
    });

    // Keep running for 10 minutes to see real-time kills after preload
    setTimeout(async () => {
      console.log('\n📊 Final Summary:');
      console.log(`   Historical kills loaded: ${historicalKills.length}`);
      console.log(`   Real-time kills received: ${realtimeKills.length}`);

      await client.disconnect();
      process.exit(0);
    }, 10 * 60 * 1000);

  } catch (error) {
    console.error('Extended preload example error:', error);
    await client.disconnect();
    process.exit(1);
  }
}

// Advanced example showing mixed subscriptions
async function advancedExample() {
  const client = new WandererKillsClient('ws://localhost:4004');

  try {
    // Connect with initial subscriptions
    await client.connect();

    // Join with both systems and characters at once
    // This creates an OR filter - you'll receive kills that match:
    // - Any of the specified systems OR
    // - Any of the specified characters (as victim or attacker)
    const channel = client.socket.channel('killmails:lobby', {
      systems: [30000142, 30002187], // Jita, Amarr
      characters: [95465499, 90379338] // Example character IDs
    });

    await new Promise((resolve, reject) => {
      channel.join()
        .receive('ok', resolve)
        .receive('error', reject);
    });

    console.log('✅ Connected with mixed subscriptions');

    // The channel will now receive killmails from:
    // 1. Jita system (30000142)
    // 2. Amarr system (30002187)
    // 3. Any system where character 95465499 gets a kill or dies
    // 4. Any system where character 90379338 gets a kill or dies

  } catch (error) {
    console.error('Advanced example error:', error);
    await client.disconnect();
  }
}

// Run the example if this file is executed directly
// For ES modules, use import.meta.url
if (import.meta.url === `file://${process.argv[1]}`) {
  // Check command line arguments to determine which example to run
  const args = process.argv.slice(2);
  const exampleType = args[0] || 'basic';

  console.log(`🚀 Running ${exampleType} example...\n`);

  switch (exampleType) {
    case 'basic':
      basicExample();
      break;
    case 'preload':
      extendedPreloadExample();
      break;
    case 'advanced':
      advancedExample();
      break;
    default:
      console.log('Usage: node websocket_client.js [basic|preload|advanced]');
      console.log('  basic    - Simple connection and subscription');
      console.log('  preload  - Extended historical data preload example');
      console.log('  advanced - Mixed system and character subscriptions');
      process.exit(1);
  }
}

export default WandererKillsClient; 