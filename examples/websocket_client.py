#!/usr/bin/env python3
"""
WandererKills WebSocket Client Example (Python)

This example shows how to connect to the WandererKills WebSocket API
to receive real-time killmail updates for specific EVE Online systems.

Dependencies:
    pip install websockets asyncio json
"""

import asyncio
import json
import logging
import signal
import sys
from typing import List, Optional, Set
import websockets
from websockets.exceptions import ConnectionClosed, WebSocketException

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class WandererKillsClient:
    """WebSocket client for WandererKills real-time killmail subscriptions."""
    
    def __init__(self, server_url: str):
        self.server_url = server_url.replace('http://', 'ws://').replace('https://', 'wss://')
        self.websocket: Optional[websockets.WebSocketServerProtocol] = None
        self.subscriptions: Set[int] = set()
        self.subscription_id: Optional[str] = None
        self.running = False
        
    async def connect(self) -> dict:
        """Connect to the WebSocket server and join the killmails channel."""
        try:
            # Establish WebSocket connection with optional client identifier
            # The client_identifier helps with debugging and appears in server logs
            client_id = "python_example_client"
            uri = f"{self.server_url}/socket/websocket?vsn=2.0.0&client_identifier={client_id}"
            logger.info(f"Connecting to {uri}")
            
            self.websocket = await websockets.connect(uri)
            self.running = True
            
            # Join the killmails channel
            join_message = {
                "topic": "killmails:lobby",
                "event": "phx_join",
                "payload": {},
                "ref": 1
            }
            
            await self.websocket.send(json.dumps(join_message))
            
            # Wait for join confirmation
            response = await self.websocket.recv()
            response_data = json.loads(response)
            
            if response_data.get("event") == "phx_reply" and response_data.get("payload", {}).get("status") == "ok":
                payload = response_data["payload"]["response"]
                self.subscription_id = payload.get("subscription_id")
                logger.info(f"✅ Connected to WandererKills WebSocket")
                logger.info(f"📋 Subscription ID: {self.subscription_id}")
                
                # Start listening for messages
                asyncio.create_task(self._listen_for_messages())
                
                return payload
            else:
                raise Exception(f"Failed to join channel: {response_data}")
                
        except Exception as e:
            logger.error(f"❌ Connection failed: {e}")
            raise
    
    async def _listen_for_messages(self):
        """Listen for incoming WebSocket messages."""
        try:
            while self.running and self.websocket:
                try:
                    message = await self.websocket.recv()
                    await self._handle_message(json.loads(message))
                except ConnectionClosed:
                    logger.warning("📡 WebSocket connection closed")
                    break
                except json.JSONDecodeError as e:
                    logger.error(f"Failed to decode message: {e}")
                except Exception as e:
                    logger.error(f"Error handling message: {e}")
                    
        except Exception as e:
            logger.error(f"Error in message listener: {e}")
        finally:
            self.running = False
    
    async def _handle_message(self, message: dict):
        """Handle incoming WebSocket messages."""
        event = message.get("event")
        payload = message.get("payload", {})
        
        if event == "killmail_update":
            system_id = payload.get("system_id")
            killmails = payload.get("killmails", [])
            timestamp = payload.get("timestamp")
            
            logger.info(f"🔥 New killmails in system {system_id}:")
            logger.info(f"   📊 Count: {len(killmails)}")
            logger.info(f"   ⏰ Timestamp: {timestamp}")
            
            for i, killmail in enumerate(killmails, 1):
                killmail_id = killmail.get("killmail_id")
                victim = killmail.get("victim", {})
                attackers = killmail.get("attackers", [])
                
                logger.info(f"   [{i}] Killmail ID: {killmail_id}")
                if victim:
                    victim_name = victim.get("character_name", "Unknown")
                    ship_name = victim.get("ship_type_name", "Unknown ship")
                    logger.info(f"       👤 Victim: {victim_name} ({ship_name})")
                
                if attackers:
                    logger.info(f"       ⚔️  Attackers: {len(attackers)}")
        
        elif event == "kill_count_update":
            system_id = payload.get("system_id")
            count = payload.get("count")
            logger.info(f"📊 Kill count update for system {system_id}: {count} kills")
        
        elif event == "phx_reply":
            # Handle command responses
            ref = message.get("ref")
            status = payload.get("status")
            response = payload.get("response", {})
            
            if status == "ok":
                logger.debug(f"✅ Command {ref} successful: {response}")
            else:
                logger.error(f"❌ Command {ref} failed: {response}")
    
    async def subscribe_to_systems(self, system_ids: List[int]) -> dict:
        """Subscribe to specific EVE Online systems."""
        if not self.websocket or not self.running:
            raise Exception("Not connected to WebSocket")
        
        message = {
            "topic": "killmails:lobby",
            "event": "subscribe_systems",
            "payload": {"systems": system_ids},
            "ref": 2
        }
        
        await self.websocket.send(json.dumps(message))
        self.subscriptions.update(system_ids)
        
        logger.info(f"✅ Subscribed to systems: {', '.join(map(str, system_ids))}")
        logger.info(f"📡 Total subscriptions: {len(self.subscriptions)}")
        
        return {"subscribed_systems": list(self.subscriptions)}
    
    async def unsubscribe_from_systems(self, system_ids: List[int]) -> dict:
        """Unsubscribe from specific EVE Online systems."""
        if not self.websocket or not self.running:
            raise Exception("Not connected to WebSocket")
        
        message = {
            "topic": "killmails:lobby",
            "event": "unsubscribe_systems",
            "payload": {"systems": system_ids},
            "ref": 3
        }
        
        await self.websocket.send(json.dumps(message))
        self.subscriptions.difference_update(system_ids)
        
        logger.info(f"❌ Unsubscribed from systems: {', '.join(map(str, system_ids))}")
        logger.info(f"📡 Remaining subscriptions: {len(self.subscriptions)}")
        
        return {"subscribed_systems": list(self.subscriptions)}
    
    async def get_status(self) -> dict:
        """Get current subscription status."""
        if not self.websocket or not self.running:
            raise Exception("Not connected to WebSocket")
        
        message = {
            "topic": "killmails:lobby",
            "event": "get_status",
            "payload": {},
            "ref": 4
        }
        
        await self.websocket.send(json.dumps(message))
        
        return {
            "subscription_id": self.subscription_id,
            "subscribed_systems": list(self.subscriptions),
            "connected": self.running
        }
    
    async def disconnect(self):
        """Disconnect from the WebSocket server."""
        self.running = False
        
        if self.websocket:
            # Send leave message
            leave_message = {
                "topic": "killmails:lobby",
                "event": "phx_leave",
                "payload": {},
                "ref": 5
            }
            
            try:
                await self.websocket.send(json.dumps(leave_message))
                await self.websocket.close()
            except:
                pass  # Ignore errors during cleanup
        
        logger.info("📴 Disconnected from WandererKills WebSocket")


async def example():
    """Example usage of the WandererKills WebSocket client."""
    client = WandererKillsClient('ws://localhost:4004')
    
    # Set up signal handler for graceful shutdown
    def signal_handler():
        logger.info("🛑 Shutdown signal received")
        asyncio.create_task(client.disconnect())
    
    # Handle SIGINT (Ctrl+C) and SIGTERM
    for sig in [signal.SIGINT, signal.SIGTERM]:
        signal.signal(sig, lambda s, f: signal_handler())
    
    try:
        # Connect to the server
        await client.connect()
        
        # Subscribe to some popular systems
        # Jita (30000142), Dodixie (30002659), Amarr (30002187)
        await client.subscribe_to_systems([30000142, 30002659, 30002187])
        
        # Get current status
        status = await client.get_status()
        logger.info(f"📋 Current status: {status}")
        
        # Keep running and listening for updates
        logger.info("🎧 Listening for killmail updates... Press Ctrl+C to stop")
        
        # Schedule unsubscription after 5 minutes
        async def delayed_unsubscribe():
            await asyncio.sleep(5 * 60)  # 5 minutes
            if client.running:
                await client.unsubscribe_from_systems([30000142])
        
        asyncio.create_task(delayed_unsubscribe())
        
        # Keep the client running until interrupted
        while client.running:
            await asyncio.sleep(1)
            
    except Exception as e:
        logger.error(f"❌ Client error: {e}")
    finally:
        await client.disconnect()


if __name__ == "__main__":
    # Run the example
    try:
        asyncio.run(example())
    except KeyboardInterrupt:
        logger.info("👋 Goodbye!")
    except Exception as e:
        logger.error(f"💥 Fatal error: {e}")
        sys.exit(1) 