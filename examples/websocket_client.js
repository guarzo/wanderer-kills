/**
 * WandererKills WebSocket Client Example
 * 
 * This example shows how to connect to the WandererKills WebSocket API
 * to receive real-time killmail updates for specific EVE Online systems.
 */

// Import Phoenix Socket (you'll need to install phoenix)
// npm install phoenix
const { Socket } = require('phoenix');

class WandererKillsClient {
  constructor(serverUrl, apiToken) {
    this.serverUrl = serverUrl;
    this.apiToken = apiToken;
    this.socket = null;
    this.channel = null;
    this.subscriptions = new Set();
  }

  /**
   * Connect to the WebSocket server
   */
  async connect() {
    return new Promise((resolve, reject) => {
      // Create socket connection
      this.socket = new Socket(`${this.serverUrl}/socket`, {
        params: { token: this.apiToken },
        timeout: 10000
      });

      // Handle connection events
      this.socket.onError((error) => {
        console.error('Socket error:', error);
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
          console.log('Connected to WandererKills WebSocket');
          console.log('Connection details:', response);
          this.setupEventHandlers();
          resolve(response);
        })
        .receive('error', (error) => {
          console.error('Failed to join channel:', error);
          reject(error);
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
   */
  disconnect() {
    if (this.channel) {
      this.channel.leave();
    }
    if (this.socket) {
      this.socket.disconnect();
    }
    console.log('Disconnected from WandererKills WebSocket');
  }
}

// Example usage
async function example() {
  const client = new WandererKillsClient('ws://localhost:4004', 'your-api-token-here');

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
    setTimeout(() => {
      client.disconnect();
    }, 10 * 60 * 1000);

  } catch (error) {
    console.error('Client error:', error);
    client.disconnect();
  }
}

// Run the example if this file is executed directly
if (require.main === module) {
  example();
}

module.exports = WandererKillsClient; 