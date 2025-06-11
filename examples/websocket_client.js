/**
 * WandererKills WebSocket Client Example
 * 
 * This example shows how to connect to the WandererKills WebSocket API
 * to receive real-time killmail updates for specific EVE Online systems.
 */

// Import Phoenix Socket (you'll need to install phoenix)
// npm install phoenix
import { Socket } from 'phoenix';

class WandererKillsClient {
  constructor(serverUrl) {
    this.serverUrl = serverUrl;
    this.socket = null;
    this.channel = null;
    this.subscriptions = new Set();
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
      
      // Process each killmail
      payload.killmails.forEach((killmail, index) => {
        console.log(`   [${index + 1}] Killmail ID: ${killmail.killmail_id}`);
        if (killmail.victim) {
          console.log(`       Victim: ${killmail.victim.character_name || 'Unknown'} (${killmail.victim.ship_type_name || 'Unknown ship'})`);
        }
        if (killmail.attackers && killmail.attackers.length > 0) {
          console.log(`       Attackers: ${killmail.attackers.length}`);
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
          systemIds.forEach(id => this.subscriptions.add(id));
          console.log(`✅ Subscribed to systems: ${systemIds.join(', ')}`);
          console.log(`📡 Total subscriptions: ${response.subscribed_systems.length}`);
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
          systemIds.forEach(id => this.subscriptions.delete(id));
          console.log(`❌ Unsubscribed from systems: ${systemIds.join(', ')}`);
          console.log(`📡 Remaining subscriptions: ${response.subscribed_systems.length}`);
          resolve(response);
        })
        .receive('error', (error) => {
          console.error('Failed to unsubscribe from systems:', error);
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

    // Get current status
    await client.getStatus();

    // Keep the connection alive for 5 minutes, then unsubscribe from Jita
    setTimeout(async () => {
      await client.unsubscribeFromSystems([30000142]);
    }, 5 * 60 * 1000);

    // Disconnect after 10 minutes
    setTimeout(async () => {
      await client.disconnect();
    }, 10 * 60 * 1000);

  } catch (error) {
    console.error('Client error:', error);
    await client.disconnect();
  }
}

// Run the example if this file is executed directly
// For ES modules, use import.meta.url
if (import.meta.url === `file://${process.argv[1]}`) {
  example();
}

export default WandererKillsClient; 