# xano_sdk — Realtime WebSocket channels for Flutter

A faithful Flutter/Dart port of the realtime channel API from the official
[Xano JS SDK](https://www.npmjs.com/package/@xano/js-sdk).

<img width="2856" height="1726" alt="CleanShot 2026-02-27 at 10 07 41@2x" src="https://github.com/user-attachments/assets/3ab5c9b3-c876-47d9-b778-abf5d6e7493f" />

## Features

| JS SDK feature | Flutter port |
|---|---|
| `xano.channel(name, options)` | `XanoRealtimeClient.channel(name, ...)` |
| `channel.on(action, fn, errFn)` | `channel.on(action, fn, onError: fn)` |
| `channel.message(payload, opts)` | `channel.message(payload, authenticated: bool)` |
| `channel.history()` | `channel.history()` |
| `channel.getPresence()` | `channel.getPresence()` |
| `channel.destroy()` | `channel.destroy()` |
| `client.message(payload)` (peer-to-peer) | `XanoRealtimePeer.message(payload)` |
| Auto-reconnect with exponential back-off | ✅ |
| Offline message queue | `queueOfflineActions: true` |
| Presence tracking | `presence: true` |

## Installation

```yaml
dependencies:
  xano_sdk:
    path: ../xano_sdk   # or publish to pub.dev
```

## Quick start

```dart
import 'package:xano_sdk/xano_sdk.dart';

// 1. Create the client — configure once per app session.
final client = XanoRealtimeClient(
  apiGroupBaseUrl: 'https://x8ki-letl-twmt.n7.xano.io/api:jVuUQATw',
  realtimeConnectionHash: 'YOUR_CONNECTION_HASH',

  // Optional — required for authenticated channels.
  // realtimeAuthToken: 'eyJhbGci...',
);

// 2. Open a channel.
final channel = client.channel(
  'chat-room',
  presence: true,          // track who is online
  history: true,           // request history on join
  queueOfflineActions: true, // buffer messages while reconnecting
);

// 3. Listen for incoming messages.
channel.on(
  XanoRealtimeAction.message,
  (msg) => print('📨 ${msg.payload}'),
  onError: (err) => print('❌ ${err.payload}'),
);

// 4. Listen for connection status changes.
channel.on(
  XanoRealtimeAction.connectionStatus,
  (msg) => print('🔌 ${msg.connectionStatus}'),
);

// 5. Listen for history (arrives after join when history=true).
channel.on(
  XanoRealtimeAction.history,
  (msg) => print('📜 History: ${msg.payload}'),
);

// 6. Listen for presence events.
channel
  .on(XanoRealtimeAction.presenceFull,   (m) => print('👥 ${channel.getPresence()}'))
  .on(XanoRealtimeAction.presenceUpdate, (m) => print('👤 ${m.payload}'));

// 7. Send a message to everyone in the channel.
channel.message({'text': 'Hello, world!'});

// 8. Send a message only to authenticated users.
channel.message({'text': 'Secret'}, authenticated: true);

// 9. Private peer-to-peer message.
final peers = channel.getPresence();
if (peers.isNotEmpty) {
  peers.first.message({'text': 'Hey!'});
}

// 10. Request history manually.
channel.history();

// 11. Tear down.
channel.destroy();
client.disconnect();
```

## Actions reference

| `XanoRealtimeAction` | Wire value | When it fires |
|---|---|---|
| `connectionStatus` | `connection_status` | WebSocket opened / closed |
| `error` | `error` | Server-side error |
| `event` | `event` | Custom Realtime Trigger event |
| `history` | `history` | Response to `channel.history()` |
| `join` | `join` | A client joined (presence) |
| `leave` | `leave` | A client left (presence) |
| `message` | `message` | Public / private message |
| `presenceFull` | `presence_full` | Full presence snapshot on join |
| `presenceUpdate` | `presence_update` | Incremental presence change |

Pass `null` as the action to receive every event type (wildcard):

```dart
channel.on(null, (msg) => print('Any: ${msg.action}'));
```

## Reconnection

The singleton `XanoRealtimeState` reconnects automatically with exponential
back-off (1 s → 2 s → 4 s … capped at 60 s) when the server closes the
socket with codes 1006, 1011–1014, or 4000.  Call `client.reconnect()` to
force a reconnect (e.g. after updating an auth token).

## Architecture

```
XanoRealtimeClient          ← public entry point (one per app)
  └─ XanoRealtimeChannel    ← one per channel subscription
       └─ XanoRealtimeState ← singleton: owns the WebSocketChannel
            └─ WebSocketChannel (web_socket_channel package)
```

All channels share one WebSocket.  The connection opens when the first
listener is registered and closes when the last channel calls `destroy()`.

## Running the example

```bash
cd example

# 1. Generate platform folders
flutter create --platforms=macos,ios,android,web .

# 2. macOS only: add network entitlement
#    In macos/Runner/DebugProfile.entitlements AND Release.entitlements, add:
#    <key>com.apple.security.network.client</key>
#    <true/>

# 3. Copy the env template and fill in your Xano values
cp lib/env.example.dart lib/env.dart

# 4. Run
flutter run
```
