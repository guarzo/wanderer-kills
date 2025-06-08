- [ ] “Define the ZKB client behaviour interface. Create `lib/zkb_service/client_behaviour.ex` with exactly these callbacks from the spec:

  ````elixir
  defmodule ZkbService.ClientBehaviour do
    @callback fetch_system_kills(system_id :: integer(), since_hours :: integer(), limit :: integer())
      :: {:ok, [kill()]} | {:error, term()}
    @callback fetch_systems_kills(system_ids :: [integer()], since_hours :: integer(), limit :: integer())
      :: {:ok, %{integer() => [kill()]}} | {:error, term()}
    @callback fetch_cached_kills(system_id :: integer()) :: [kill()]
    @callback fetch_cached_kills_for_systems(system_ids :: [integer()]) :: %{integer() => [kill()]}
    @callback subscribe_to_kills(subscriber_id :: String.t(), system_ids :: [integer()], callback_url :: String.t() | nil)
      :: {:ok, subscription_id :: String.t()} | {:error, term()}
    @callback unsubscribe_from_kills(subscriber_id :: String.t()) :: :ok | {:error, term()}
    @callback get_killmail(killmail_id :: integer()) :: kill() | nil
    @callback get_system_kill_count(system_id :: integer()) :: integer()
  end
  ```”

  ````

- [ ] “Implement the behaviour in your existing ZKB client. In `lib/wanderer_kills/zkb/client.ex` add `@behaviour ZkbService.ClientBehaviour` and implement:

  - `fetch_systems_kills/3` by batching calls to `fetch_system_kills/3` and aggregating results
  - `fetch_cached_kills/1` and `fetch_cached_kills_for_systems/1` by delegating to your cache module
  - `subscribe_to_kills/3` and `unsubscribe_from_kills/1` via a new `ZkbService.SubscriptionManager` GenServer
  - `get_killmail/1` by reusing your existing killmail lookup
  - `get_system_kill_count/1` via your cache or direct store”

- [ ] “Scope and add HTTP routes under `/api/v1`. In `lib/wanderer_kills_web/router.ex`:

  ````elixir
  scope "/api/v1", WandererKillsWeb do
    get   "/kills/system/:system_id",       KillsController, :list
    post  "/kills/systems",                KillsController, :bulk
    get   "/kills/cached/:system_id",      KillsController, :cached
    get   "/killmail/:killmail_id",        KillsController, :show
    get   "/kills/count/:system_id",       KillsController, :count
    post  "/subscriptions",                SubscriptionsController, :create
    delete "/subscriptions/:subscriber_id", SubscriptionsController, :delete
  end
  ```”

  ````

- [ ] “Create `Api.KillsController` (`lib/wanderer_kills_web/controllers/kills_controller.ex`) with actions:

  - `list(conn, %{"system_id" => id, "since_hours" => h, "limit" => l})` → call `fetch_system_kills/3`, render JSON array
  - `bulk(conn, params)` → validate `system_ids`, `since_hours`, `limit`, call `fetch_systems_kills/3`, render `%{systems_kills: …, timestamp: …}`
  - `cached(conn, %{"system_id" => id})` → call `fetch_cached_kills/1`, render JSON array
  - `show(conn, %{"killmail_id" => id})` → call `get_killmail/1`, 404 if nil
  - `count(conn, %{"system_id" => id})` → call `get_system_kill_count/1`, render `%{system_id: id, count: n, timestamp: …}`”

- [ ] “Create `Api.SubscriptionsController` (`lib/wanderer_kills_web/controllers/subscriptions_controller.ex`) with:

  - `create(conn, %{"subscriber_id" => sid, "system_ids" => ids, "callback_url" => url})` → call `subscribe_to_kills/3`, render `{subscription_id, status}`
  - `delete(conn, %{"subscriber_id" => sid})` → call `unsubscribe_from_kills/1`, render status”

- [ ] “Implement `ZkbService.SubscriptionManager` (`lib/zkb_service/subscription_manager.ex`) as a GenServer or ETS-backed store to:

  - Track `{subscriber_id, system_ids, callback_url}`
  - Expose `subscribe/3` and `unsubscribe/1` that satisfy the behaviour
  - On each new fetch, dispatch HTTP POSTs to `callback_url` (if given) and broadcast via Phoenix.PubSub”

- [ ] “Add PubSub broadcasts in your fetch loop. After caching new kills or counts, call:
  ```elixir
  Phoenix.PubSub.broadcast(ZkbService.PubSub, "zkb:kills:updated", %{…})
  Phoenix.PubSub.broadcast(ZkbService.PubSub, "zkb:system:#{system_id}", %{…})
  Use the message formats (:systems_kill_update, etc.) exactly as in the spec.”
  ```

“Define the kill() struct/type. Create lib/zkb_service/types.ex:

elixir
Copy
Edit
@type kill :: %{
killmail_id: integer(),
kill_time: DateTime.t(),
solar_system_id: integer(),
victim: %{…},
attackers: [ … ]
}

```”

 “Centralize JSON response envelopes. In lib/wanderer_kills_web/controllers/helpers.ex add:

elixir
Copy
Edit
def render_success(conn, data), do: json(conn, %{data: data, timestamp: …})
def render_error(conn, code, msg, details \\ nil), do: json(conn, %{error: msg, code: code, details: details, timestamp: …})
And use these in all controller actions.”

 “Implement the WebSocket channel. In lib/wanderer_kills_web/channels/kills_channel.ex:

Handle join("zkb:subscriber:" <> subscriber_id, _payload, socket)

Handle "subscribe"/"unsubscribe" messages, routing them to your SubscriptionManager

Push inbound PubSub messages to the socket client”

Copy
Edit
```
