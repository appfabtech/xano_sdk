import 'xano_realtime_channel.dart';
import 'xano_realtime_state.dart';

/// Entry point for Xano realtime WebSocket channels.
///
/// Mirrors the realtime surface of `XanoClient` from the JS SDK.
///
/// ## Setup
/// ```dart
/// final client = XanoRealtimeClient(
///   apiGroupBaseUrl: 'https://x8ki-letl-twmt.n7.xano.io/api:jVuUQATw',
///   realtimeConnectionHash: 'YOUR_CONNECTION_HASH',
/// );
/// ```
///
/// For authenticated channels:
/// ```dart
/// final client = XanoRealtimeClient(
///   apiGroupBaseUrl: '...',
///   realtimeConnectionHash: '...',
///   realtimeAuthToken: 'eyJhbGci...',
/// );
/// ```
///
/// ## Opening a channel
/// ```dart
/// final ch = client.channel(
///   'chat-room',
///   presence: true,
///   history: true,
///   queueOfflineActions: true,
/// );
///
/// ch.on(XanoRealtimeAction.message, (msg) => print(msg.payload));
/// ch.message({'text': 'Hello!'});
/// ```
///
/// ## Cleanup
/// ```dart
/// ch.destroy();
/// client.disconnect();
/// ```
class XanoRealtimeClient {
  final String apiGroupBaseUrl;
  final String realtimeConnectionHash;
  final String? realtimeAuthToken;

  final XanoRealtimeState _state;

  XanoRealtimeClient({
    required this.apiGroupBaseUrl,
    required this.realtimeConnectionHash,
    this.realtimeAuthToken,
  }) : _state = XanoRealtimeState.instance {
    _state.configure(
      apiGroupBaseUrl: apiGroupBaseUrl,
      realtimeConnectionHash: realtimeConnectionHash,
      realtimeAuthToken: realtimeAuthToken,
    );
  }

  // ── auth token helpers (mirrors JS SDK) ─────────────────────────────────────

  /// Whether a realtime auth token has been set.
  bool get hasRealtimeAuthToken => realtimeAuthToken != null;

  /// Update the auth token at runtime (e.g. after login).
  ///
  /// Mirrors `xanoClient.setRealtimeAuthToken(token)` in the JS SDK.
  /// Call [reconnect] afterwards to re-establish the connection with the
  /// new token.
  void setRealtimeAuthToken(String? token) {
    _state.setRealtimeAuthToken(token);
  }

  // ── channel factory ─────────────────────────────────────────────────────────

  /// Opens (or joins) a realtime channel with the given [name].
  ///
  /// The WebSocket connection is established lazily the first time a listener
  /// is added via [XanoRealtimeChannel.on].
  ///
  /// Parameters mirror the JS SDK's `xano.channel(name, options)`:
  /// - [presence]           — enable presence tracking.
  /// - [history]            — request message history on join.
  /// - [queueOfflineActions]— buffer outbound messages while offline.
  XanoRealtimeChannel channel(
    String name, {
    bool presence = false,
    bool history = false,
    bool queueOfflineActions = false,
  }) {
    return XanoRealtimeChannel(
      name,
      XanoChannelOptions(
        presence: presence,
        history: history,
        queueOfflineActions: queueOfflineActions,
      ),
      _state,
    );
  }

  // ── connection control ──────────────────────────────────────────────────────

  /// Force a reconnect on all open channels.
  ///
  /// Useful after updating [realtimeAuthToken] to trigger re-authentication.
  /// Mirrors `xano.realtimeReconnect()` in the JS SDK.
  void reconnect() => _state.reconnect();

  /// Explicitly close the WebSocket and stop reconnecting.
  ///
  /// All channels will stop receiving messages. To resume, create new channels.
  void disconnect() => _state.disconnect();
}
