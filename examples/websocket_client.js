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
   * @param {number} timeout - Connection timeout in milliseconds (default: 10000)
   * @returns {Promise} Resolves when connected, rejects on error or timeout
   */
  async connect(timeout = 10000) {
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

      // Join the killmails channel
      this.channel = this.socket.channel('killmails:lobby', {});

      this.channel.join()
        .receive('ok', (response) => {
          clearTimeout(timeoutId);
          console.log('Connected to WandererKills WebSocket');
          console.log('Connection details:', response);
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

// Example usage
async function example() {
  const client = new WandererKillsClient('ws://localhost:4004');

  try {
    // Connect to the server
    await client.connect();

    // Subscribe to some popular systems
    // Jita (30000142), Dodixie (30002659), Amarr (30002187)
    await client.subscribeToSystems([30000142, 30002659, 30002187]);

    // Subscribe to specific characters (example character IDs)
    // These will track kills where these characters appear as victim or attacker
    await client.subscribeToCharacters([95465499, 90379338]);

    // Get current status
    await client.getStatus();

    // Example: Subscribe to more characters after 2 minutes
    setTimeout(async () => {
      console.log('\n📍 Adding more character subscriptions...');
      await client.subscribeToCharacters([12345678, 87654321]);
      await client.getStatus();
    }, 2 * 60 * 1000);

    // Example: Unsubscribe from Jita after 5 minutes
    setTimeout(async () => {
      console.log('\n📍 Unsubscribing from Jita...');
      await client.unsubscribeFromSystems([30000142]);
    }, 5 * 60 * 1000);

    // Example: Unsubscribe from some characters after 7 minutes
    setTimeout(async () => {
      console.log('\n📍 Unsubscribing from some characters...');
      await client.unsubscribeFromCharacters([95465499]);
      await client.getStatus();
    }, 7 * 60 * 1000);

    // Disconnect after 10 minutes
    setTimeout(async () => {
      console.log('\n📍 Disconnecting...');
      await client.disconnect();
      process.exit(0);
    }, 10 * 60 * 1000);

  } catch (error) {
    console.error('Client error:', error);
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
  example();
}

export default WandererKillsClient; 