#!/usr/bin/env python3
"""
WandererKills WebSocket Client Example (Python)

This example shows how to connect to the WandererKills WebSocket API
to receive real-time killmail updates for:
- Specific EVE Online systems
- Specific characters (as victim or attacker)

Features:
- System-based subscriptions: Monitor specific solar systems
- Character-based subscriptions: Track when specific characters get kills or die
- Mixed subscriptions: Combine both system and character filters (OR logic)
- Real-time updates: Receive killmails as they happen
- Historical preload: Get recent kills when first subscribing
- Extended preload: Request historical data with progressive delivery

Dependencies:
    pip install websockets asyncio

Note: This is a simplified Phoenix Channel client implementation.
For production use, consider using a full Phoenix Channel client library.
"""

import asyncio
import json
import logging
import signal
import sys
import time
from typing import Optional, Dict, List, Any
import websockets
from websockets.exceptions import ConnectionClosed, WebSocketException

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class PhoenixChannel:
    """Simplified Phoenix Channel implementation for Python."""
    
    def __init__(self, socket, topic: str, params: Dict[str, Any] = None):
        self.socket = socket
        self.topic = topic
        self.params = params or {}
        self.joined = False
        self.ref = 0
        self.join_ref = None
        self.push_callbacks = {}
        self.event_handlers = {}
        
    def _next_ref(self) -> str:
        """Generate next message reference."""
        self.ref += 1
        return str(self.ref)
    
    async def join(self) -> Dict[str, Any]:
        """Join the channel."""
        ref = self._next_ref()
        self.join_ref = ref
        
        message = {
            "topic": self.topic,
            "event": "phx_join",
            "payload": self.params,
            "ref": ref,
            "join_ref": ref
        }
        
        # Create a future to wait for the response
        future = asyncio.Future()
        self.push_callbacks[ref] = future
        
        await self.socket.send(json.dumps(message))
        
        # Wait for response
        try:
            result = await asyncio.wait_for(future, timeout=5.0)
            if result.get("status") == "ok":
                self.joined = True
                return result.get("response", {})
            else:
                raise Exception(f"Failed to join channel: {result}")
        except asyncio.TimeoutError:
            raise Exception("Timeout waiting for channel join")
    
    async def push(self, event: str, payload: Dict[str, Any]) -> Dict[str, Any]:
        """Push a message to the channel."""
        if not self.joined:
            raise Exception("Must join channel before pushing messages")
            
        ref = self._next_ref()
        
        message = {
            "topic": self.topic,
            "event": event,
            "payload": payload,
            "ref": ref,
            "join_ref": self.join_ref
        }
        
        # Create a future to wait for the response
        future = asyncio.Future()
        self.push_callbacks[ref] = future
        
        await self.socket.send(json.dumps(message))
        
        # Wait for response
        try:
            result = await asyncio.wait_for(future, timeout=5.0)
            return result
        except asyncio.TimeoutError:
            raise Exception(f"Timeout waiting for response to {event}")
    
    def on(self, event: str, callback):
        """Register an event handler."""
        if event not in self.event_handlers:
            self.event_handlers[event] = []
        self.event_handlers[event].append(callback)
    
    async def handle_message(self, message: Dict[str, Any]):
        """Handle incoming message for this channel."""
        event = message.get("event")
        ref = message.get("ref")
        payload = message.get("payload", {})
        
        # Handle push responses
        if event == "phx_reply" and ref in self.push_callbacks:
            future = self.push_callbacks.pop(ref)
            if not future.done():
                future.set_result(payload)
            return
        
        # Handle broadcast events
        if event in self.event_handlers:
            for handler in self.event_handlers[event]:
                try:
                    if asyncio.iscoroutinefunction(handler):
                        await handler(payload)
                    else:
                        handler(payload)
                except Exception as e:
                    logger.error(f"Error in event handler for {event}: {e}")


class WandererKillsClient:
    """WebSocket client for WandererKills real-time killmail subscriptions."""
    
    def __init__(self, server_url: str):
        self.server_url = server_url.replace('http://', 'ws://').replace('https://', 'wss://')
        self.websocket: Optional[websockets.WebSocketServerProtocol] = None
        self.channel: Optional[PhoenixChannel] = None
        self.subscribed_systems: set[int] = set()
        self.subscribed_characters: set[int] = set()
        self.subscription_id: Optional[str] = None
        self.running = False
        self.heartbeat_task = None
        self.heartbeat_ref = 0
        
    async def connect(self, systems: List[int] = None, character_ids: List[int] = None, 
                     preload: Dict[str, Any] = None) -> Dict[str, Any]:
        """
        Connect to the WebSocket server and join the killmails channel.
        
        Args:
            systems: List of system IDs to subscribe to
            character_ids: List of character IDs to track (as victim or attacker)
            preload: Extended preload configuration dict
        """
        try:
            # Establish WebSocket connection
            client_id = "python_example_client"
            uri = f"{self.server_url}/socket/websocket?vsn=2.0.0&client_identifier={client_id}"
            logger.info(f"Connecting to {uri}")
            
            self.websocket = await websockets.connect(uri)
            self.running = True
            
            # Start message listener
            asyncio.create_task(self._listen_for_messages())
            
            # Start heartbeat
            self.heartbeat_task = asyncio.create_task(self._heartbeat())
            
            # Build channel params
            channel_params = {}
            if systems:
                channel_params["systems"] = systems
                self.subscribed_systems.update(systems)
            if character_ids:
                channel_params["character_ids"] = character_ids
                self.subscribed_characters.update(character_ids)
            if preload:
                channel_params["preload"] = preload
            
            # Join the killmails channel
            self.channel = PhoenixChannel(self.websocket, "killmails:lobby", channel_params)
            
            # Set up event handlers
            self._setup_event_handlers()
            
            # Join channel
            response = await self.channel.join()
            
            self.subscription_id = response.get("subscription_id")
            logger.info(f"✅ Connected to WandererKills WebSocket")
            logger.info(f"📋 Connection details: {response}")
            
            return response
            
        except Exception as e:
            logger.error(f"❌ Connection failed: {e}")
            await self.disconnect()
            raise
    
    def _setup_event_handlers(self):
        """Set up event handlers for the channel."""
        # Killmail updates
        self.channel.on("killmail_update", self._handle_killmail_update)
        
        # Kill count updates
        self.channel.on("kill_count_update", self._handle_kill_count_update)
        
        # Extended preload events
        self.channel.on("preload_status", self._handle_preload_status)
        self.channel.on("preload_batch", self._handle_preload_batch)
        self.channel.on("preload_complete", self._handle_preload_complete)
    
    def _handle_killmail_update(self, payload: Dict[str, Any]):
        """Handle killmail update events."""
        system_id = payload.get("system_id")
        killmails = payload.get("killmails", [])
        timestamp = payload.get("timestamp")
        is_preload = payload.get("preload", False)
        
        logger.info(f"🔥 New killmails in system {system_id}:")
        logger.info(f"   Killmails: {len(killmails)}")
        logger.info(f"   Timestamp: {timestamp}")
        logger.info(f"   Preload: {'Yes (historical data)' if is_preload else 'No (real-time)'}")
        
        for i, killmail in enumerate(killmails[:3], 1):  # Show first 3
            killmail_id = killmail.get("killmail_id")
            victim = killmail.get("victim", {})
            attackers = killmail.get("attackers", [])
            zkb = killmail.get("zkb", {})
            
            logger.info(f"   [{i}] Killmail ID: {killmail_id}")
            if victim:
                victim_name = victim.get("character_name", "Unknown")
                ship_name = victim.get("ship_name", "Unknown ship")
                corp_name = victim.get("corporation_name", "Unknown")
                logger.info(f"       Victim: {victim_name} ({ship_name})")
                logger.info(f"       Corporation: {corp_name}")
            
            if attackers:
                logger.info(f"       Attackers: {len(attackers)}")
                final_blow = next((a for a in attackers if a.get("final_blow")), None)
                if final_blow:
                    attacker_name = final_blow.get("character_name", "Unknown")
                    attacker_ship = final_blow.get("ship_name", "Unknown ship")
                    logger.info(f"       Final blow: {attacker_name} ({attacker_ship})")
            
            if zkb:
                total_value = zkb.get("total_value", 0)
                logger.info(f"       Value: {total_value / 1000000:.2f}M ISK")
    
    def _handle_kill_count_update(self, payload: Dict[str, Any]):
        """Handle kill count update events."""
        system_id = payload.get("system_id")
        count = payload.get("count")
        logger.info(f"📊 Kill count update for system {system_id}: {count} kills")
    
    def _handle_preload_status(self, payload: Dict[str, Any]):
        """Handle preload status updates."""
        logger.info(f"⏳ Preload progress: {payload.get('status')}")
        logger.info(f"   Current system: {payload.get('current_system', 'N/A')}")
        logger.info(f"   Systems complete: {payload.get('systems_complete')}/{payload.get('total_systems')}")
    
    def _handle_preload_batch(self, payload: Dict[str, Any]):
        """Handle preload batch events."""
        kills = payload.get("kills", [])
        logger.info(f"📦 Received preload batch: {len(kills)} historical kills")
        for kill in kills[:3]:  # Show first 3
            logger.info(f"   Historical kill {kill.get('killmail_id')} from {kill.get('kill_time')}")
    
    def _handle_preload_complete(self, payload: Dict[str, Any]):
        """Handle preload complete events."""
        logger.info(f"✅ Preload complete!")
        logger.info(f"   Total kills loaded: {payload.get('total_kills')}")
        logger.info(f"   Systems processed: {payload.get('systems_processed')}")
        errors = payload.get("errors", [])
        if errors:
            logger.info(f"   ⚠️ Errors encountered: {len(errors)}")
            for err in errors:
                logger.info(f"      - {err}")
    
    async def _heartbeat(self):
        """Send periodic heartbeat messages to keep connection alive."""
        while self.running:
            try:
                await asyncio.sleep(30)  # Send heartbeat every 30 seconds
                
                if self.websocket and not self.websocket.closed:
                    self.heartbeat_ref += 1
                    heartbeat_msg = {
                        "topic": "phoenix",
                        "event": "heartbeat",
                        "payload": {},
                        "ref": str(self.heartbeat_ref)
                    }
                    await self.websocket.send(json.dumps(heartbeat_msg))
                    logger.debug("💓 Heartbeat sent")
            except Exception as e:
                logger.error(f"Error sending heartbeat: {e}")
    
    async def _listen_for_messages(self):
        """Listen for incoming WebSocket messages."""
        try:
            while self.running and self.websocket:
                try:
                    message = await self.websocket.recv()
                    data = json.loads(message)
                    
                    # Route message to appropriate channel
                    topic = data.get("topic")
                    if topic == "killmails:lobby" and self.channel:
                        await self.channel.handle_message(data)
                    elif topic == "phoenix" and data.get("event") == "phx_reply":
                        # Heartbeat response, ignore
                        pass
                    else:
                        logger.debug(f"Unhandled message: {data}")
                        
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
    
    async def subscribe_to_systems(self, system_ids: List[int]) -> Dict[str, Any]:
        """Subscribe to specific EVE Online systems."""
        if not self.channel or not self.channel.joined:
            raise Exception("Not connected to channel")
        
        result = await self.channel.push("subscribe_systems", {"systems": system_ids})
        
        if result.get("status") == "ok":
            response = result.get("response", {})
            self.subscribed_systems.update(system_ids)
            logger.info(f"✅ Subscribed to systems: {', '.join(map(str, system_ids))}")
            logger.info(f"📡 Total system subscriptions: {len(response.get('subscribed_systems', []))}")
            return response
        else:
            raise Exception(f"Failed to subscribe: {result}")
    
    async def unsubscribe_from_systems(self, system_ids: List[int]) -> Dict[str, Any]:
        """Unsubscribe from specific EVE Online systems."""
        if not self.channel or not self.channel.joined:
            raise Exception("Not connected to channel")
        
        result = await self.channel.push("unsubscribe_systems", {"systems": system_ids})
        
        if result.get("status") == "ok":
            response = result.get("response", {})
            self.subscribed_systems.difference_update(system_ids)
            logger.info(f"❌ Unsubscribed from systems: {', '.join(map(str, system_ids))}")
            logger.info(f"📡 Remaining system subscriptions: {len(response.get('subscribed_systems', []))}")
            return response
        else:
            raise Exception(f"Failed to unsubscribe: {result}")
    
    async def subscribe_to_characters(self, character_ids: List[int]) -> Dict[str, Any]:
        """Subscribe to specific characters (track as victim or attacker)."""
        if not self.channel or not self.channel.joined:
            raise Exception("Not connected to channel")
        
        result = await self.channel.push("subscribe_characters", {"character_ids": character_ids})
        
        if result.get("status") == "ok":
            response = result.get("response", {})
            self.subscribed_characters.update(character_ids)
            logger.info(f"✅ Subscribed to characters: {', '.join(map(str, character_ids))}")
            logger.info(f"👤 Total character subscriptions: {len(response.get('subscribed_characters', []))}")
            return response
        else:
            raise Exception(f"Failed to subscribe: {result}")
    
    async def unsubscribe_from_characters(self, character_ids: List[int]) -> Dict[str, Any]:
        """Unsubscribe from specific characters."""
        if not self.channel or not self.channel.joined:
            raise Exception("Not connected to channel")
        
        result = await self.channel.push("unsubscribe_characters", {"character_ids": character_ids})
        
        if result.get("status") == "ok":
            response = result.get("response", {})
            self.subscribed_characters.difference_update(character_ids)
            logger.info(f"❌ Unsubscribed from characters: {', '.join(map(str, character_ids))}")
            logger.info(f"👤 Remaining character subscriptions: {len(response.get('subscribed_characters', []))}")
            return response
        else:
            raise Exception(f"Failed to unsubscribe: {result}")
    
    async def get_status(self) -> Dict[str, Any]:
        """Get current subscription status."""
        if not self.channel or not self.channel.joined:
            raise Exception("Not connected to channel")
        
        result = await self.channel.push("get_status", {})
        
        if result.get("status") == "ok":
            response = result.get("response", {})
            logger.info(f"📋 Current status:")
            logger.info(f"   Subscription ID: {response.get('subscription_id')}")
            logger.info(f"   Subscribed systems: {len(response.get('subscribed_systems', []))}")
            logger.info(f"   Subscribed characters: {len(response.get('subscribed_characters', []))}")
            return response
        else:
            raise Exception(f"Failed to get status: {result}")
    
    async def disconnect(self):
        """Disconnect from the WebSocket server."""
        self.running = False
        
        # Cancel heartbeat
        if self.heartbeat_task:
            self.heartbeat_task.cancel()
        
        if self.websocket:
            try:
                await self.websocket.close()
            except (ConnectionClosed, WebSocketException):
                pass  # Ignore errors during cleanup
        
        logger.info("📴 Disconnected from WandererKills WebSocket")


async def basic_example():
    """Basic example showing simple connection and subscription."""
    client = WandererKillsClient('ws://localhost:4004')
    
    try:
        # Connect to the server
        await client.connect()
        
        # Subscribe to some popular systems
        # Jita (30000142), Dodixie (30002659), Amarr (30002187)
        await client.subscribe_to_systems([30000142, 30002659, 30002187])
        
        # Subscribe to specific characters (example character IDs)
        # These will track kills where these characters appear as victim or attacker
        await client.subscribe_to_characters([95465499, 90379338])
        
        # Get current status
        await client.get_status()
        
        # Keep running for 5 minutes
        logger.info("🎧 Listening for killmail updates... Press Ctrl+C to stop")
        await asyncio.sleep(5 * 60)
        
    except Exception as e:
        logger.error(f"❌ Client error: {e}")
    finally:
        await client.disconnect()


async def preload_example():
    """Example with extended historical data preload."""
    client = WandererKillsClient('ws://localhost:4004')
    
    try:
        # Connect with initial systems and extended preload configuration
        await client.connect(
            systems=[30000142, 30002187],  # Jita and Amarr
            character_ids=[95465499],       # Track specific character
            preload={
                "enabled": True,
                "limit_per_system": 50,     # Get up to 50 kills per system
                "since_hours": 72,          # Look back 3 days
                "delivery_batch_size": 10,  # Deliver in batches of 10
                "delivery_interval_ms": 500 # 500ms between batches
            }
        )
        
        logger.info("🚀 Connected with extended preload configuration")
        
        # Keep running for 10 minutes to see real-time kills after preload
        await asyncio.sleep(10 * 60)
        
    except Exception as e:
        logger.error(f"❌ Client error: {e}")
    finally:
        await client.disconnect()


async def advanced_example():
    """Advanced example showing dynamic subscription management."""
    client = WandererKillsClient('ws://localhost:4004')
    
    try:
        # Connect with initial subscriptions
        await client.connect(
            systems=[30000142, 30002187],       # Jita, Amarr
            character_ids=[95465499, 90379338]  # Example character IDs
        )
        
        logger.info("✅ Connected with mixed subscriptions")
        
        # Wait 30 seconds, then add more subscriptions
        await asyncio.sleep(30)
        logger.info("\n📝 Adding more subscriptions...")
        
        # Add more systems
        await client.subscribe_to_systems([30002659])  # Dodixie
        
        # Add more characters
        await client.subscribe_to_characters([12345678])  # Example character
        
        # Get updated status
        await client.get_status()
        
        # Wait another 30 seconds, then remove some subscriptions
        await asyncio.sleep(30)
        logger.info("\n📝 Removing some subscriptions...")
        
        # Remove a system
        await client.unsubscribe_from_systems([30000142])  # Remove Jita
        
        # Remove a character
        await client.unsubscribe_from_characters([90379338])
        
        # Get final status
        await client.get_status()
        
        # Keep running for remaining time
        await asyncio.sleep(4 * 60)
        
    except Exception as e:
        logger.error(f"❌ Client error: {e}")
    finally:
        await client.disconnect()


async def main():
    """Main entry point with signal handling."""
    # Set up signal handler for graceful shutdown
    stop_event = asyncio.Event()
    
    def signal_handler():
        logger.info("🛑 Shutdown signal received")
        stop_event.set()
    
    # Handle SIGINT (Ctrl+C) and SIGTERM
    for sig in [signal.SIGINT, signal.SIGTERM]:
        signal.signal(sig, lambda s, f: signal_handler())
    
    # Check command line arguments
    example_type = sys.argv[1] if len(sys.argv) > 1 else "basic"
    
    logger.info(f"🚀 Running {example_type} example...\n")
    
    # Create task for the selected example
    if example_type == "basic":
        example_task = asyncio.create_task(basic_example())
    elif example_type == "preload":
        example_task = asyncio.create_task(preload_example())
    elif example_type == "advanced":
        example_task = asyncio.create_task(advanced_example())
    else:
        logger.error("Usage: python websocket_client.py [basic|preload|advanced]")
        logger.error("  basic    - Simple connection and subscription")
        logger.error("  preload  - Extended historical data preload example")
        logger.error("  advanced - Dynamic subscription management")
        sys.exit(1)
    
    # Wait for either the example to complete or stop signal
    done, pending = await asyncio.wait(
        [example_task, asyncio.create_task(stop_event.wait())],
        return_when=asyncio.FIRST_COMPLETED
    )
    
    # Cancel any pending tasks
    for task in pending:
        task.cancel()
    
    logger.info("👋 Goodbye!")


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        pass  # Handled by signal handler
    except Exception as e:
        logger.error(f"💥 Fatal error: {e}")
        sys.exit(1)