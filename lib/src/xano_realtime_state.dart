import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:web_socket_channel/web_socket_channel.dart';

import 'xano_realtime_action.dart';
import 'xano_realtime_message.dart';

/// Singleton that owns the single [WebSocketChannel] for a Xano workspace.
///
/// Mirrors `XanoRealtimeState` from the JS SDK.  All [XanoRealtimeChannel]
/// instances share this one connection; it auto-reconnects with exponential
/// back-off (1 s -> 60 s cap) on close codes that indicate a server-side
/// restart or forced reconnect (1006, 1011-1014, 4000).
class XanoRealtimeState {
  XanoRealtimeState._();
  static final XanoRealtimeState instance = XanoRealtimeState._();

  // -- configuration ----------------------------------------------------------
  String? _apiGroupBaseUrl;
  String? _realtimeConnectionHash;
  String? _realtimeAuthToken;

  void configure({
    required String apiGroupBaseUrl,
    required String realtimeConnectionHash,
    String? realtimeAuthToken,
  }) {
    // Guard: prevent silent reconfiguration while a socket is open.
    if (_channel != null &&
        (_apiGroupBaseUrl != apiGroupBaseUrl ||
            _realtimeConnectionHash != realtimeConnectionHash)) {
      throw StateError(
        'Cannot reconfigure XanoRealtimeState while a WebSocket is open. '
        'Call disconnect() on the existing client first.',
      );
    }
    _apiGroupBaseUrl = apiGroupBaseUrl;
    _realtimeConnectionHash = realtimeConnectionHash;
    _realtimeAuthToken = realtimeAuthToken;
  }

  /// Update only the auth token. Call [reconnect] afterwards to apply.
  void setRealtimeAuthToken(String? token) {
    _realtimeAuthToken = token;
  }

  // -- socket -----------------------------------------------------------------
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;

  WebSocketChannel? get socket => _channel;

  // -- broadcast stream (all listeners get every message) ---------------------
  final StreamController<XanoRealtimeMessage> _controller =
      StreamController<XanoRealtimeMessage>.broadcast();

  Stream<XanoRealtimeMessage> get messages => _controller.stream;

  // -- reconnect state --------------------------------------------------------
  static const int _defaultInterval = 1000; // ms
  int _reconnectInterval = _defaultInterval;
  bool _reconnecting = false;
  bool _intentionalClose = false;
  Timer? _reconnectTimer;

  // -- observer count (mirrors JS Observable onObserverCountChange) -----------
  int _observerCount = 0;

  void _onObserverCountChanged(int count) {
    _observerCount = count;
    if (count > 0) {
      _connect();
    } else {
      _closeAndCleanUp();
    }
  }

  /// Called by [XanoRealtimeChannel] when it subscribes a listener.
  void incrementObservers() => _onObserverCountChanged(_observerCount + 1);

  /// Called by [XanoRealtimeChannel] when it removes its listener.
  void decrementObservers() {
    if (_observerCount <= 0) return;
    _onObserverCountChanged(_observerCount - 1);
  }

  // -- connection -------------------------------------------------------------
  void _connect() {
    if (_channel != null) return; // already connected

    assert(_apiGroupBaseUrl != null && _realtimeConnectionHash != null,
        'Call XanoRealtimeClient.channel() after constructing XanoRealtimeClient.');

    final base = Uri.parse(_apiGroupBaseUrl!);
    final wsUri = Uri(
      scheme: 'wss',
      host: base.host,
      path: '/rt/${_realtimeConnectionHash!}',
    );

    // The JS SDK passes the realtimeAuthToken as the WebSocket sub-protocol.
    final protocols =
        _realtimeAuthToken != null ? [_realtimeAuthToken!] : <String>[];

    _intentionalClose = false;
    _channel = WebSocketChannel.connect(wsUri, protocols: protocols);

    // The JS SDK emits ConnectionStatus.Connected from the WebSocket 'open'
    // event (client-side). web_socket_channel exposes a `ready` future that
    // completes when the connection is established.
    _channel!.ready.then((_) {
      _resetBackoff();
      _controller.add(XanoRealtimeMessage(
        action: XanoRealtimeAction.connectionStatus,
        options: {},
        payload: {'status': XanoConnectionStatus.connected.wire},
      ));
    }).catchError((_) {
      // Connection failed; _onDone will handle reconnect.
    });

    _subscription = _channel!.stream.listen(
      _onData,
      onDone: _onDone,
      onError: _onError,
      cancelOnError: false,
    );
  }

  /// Internal close used when the last observer leaves.
  void _closeAndCleanUp() {
    _intentionalClose = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _subscription?.cancel();
    _channel?.sink.close(1000);
    _channel = null;
    _subscription = null;
  }

  /// Explicitly close the WebSocket and stop reconnecting.
  ///
  /// All channels will stop receiving messages. To resume, create a new
  /// [XanoRealtimeClient] and open channels again.
  void disconnect() {
    _closeAndCleanUp();
    _resetBackoff();
  }

  /// Force a reconnect -- equivalent to `realtimeReconnect()` on XanoClient.
  ///
  /// Closes the current socket with code 4000, triggering the automatic
  /// reconnection with exponential back-off.
  void reconnect() {
    _channel?.sink.close(4000);
  }

  // -- WebSocket event handlers -----------------------------------------------
  void _onData(dynamic raw) {
    if (raw is! String) return;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final msg = XanoRealtimeMessage.fromJson(json);

      // A successful message means the connection is alive. Reset backoff.
      if (_reconnecting) {
        _resetBackoff();
      }

      _controller.add(msg);
    } catch (_) {
      // malformed frame -- ignore
    }
  }

  void _onDone() {
    final closeCode = _channel?.closeCode;
    _channel = null;
    _subscription = null;

    // Notify listeners of disconnected status.
    _controller.add(XanoRealtimeMessage(
      action: XanoRealtimeAction.connectionStatus,
      options: {},
      payload: {'status': XanoConnectionStatus.disconnected.wire},
    ));

    if (_intentionalClose || _observerCount <= 0) return;

    // Only auto-reconnect for codes that indicate a recoverable close.
    // A null close code (abnormal closure) is also treated as recoverable.
    if (closeCode == null || _reconnectCodes.contains(closeCode)) {
      _scheduleReconnect();
    }
  }

  void _onError(Object error) {
    // Swallow transport errors; _onDone will fire next and handle reconnect.
  }

  // -- reconnect with exponential back-off ------------------------------------
  static const Set<int> _reconnectCodes = {1006, 1011, 1012, 1013, 1014, 4000};

  void _scheduleReconnect() {
    // Cancel any pending timer to avoid stacking.
    _reconnectTimer?.cancel();

    _reconnecting = true;
    _reconnectTimer = Timer(Duration(milliseconds: _reconnectInterval), () {
      _reconnectTimer = null;
      if (_observerCount > 0) {
        _connect();
        // Exponential back-off: double each attempt, cap at 60 s.
        _reconnectInterval = (_reconnectInterval * 2).clamp(0, 60000);
      }
    });
  }

  void _resetBackoff() {
    _reconnectInterval = _defaultInterval;
    _reconnecting = false;
  }

  // -- testing hooks ----------------------------------------------------------

  /// Inject a message into the broadcast stream without a real WebSocket.
  @visibleForTesting
  void emitForTest(XanoRealtimeMessage msg) => _controller.add(msg);

  /// Reset all internal state. Use in test tearDown to isolate tests.
  @visibleForTesting
  void resetForTest() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _subscription?.cancel();
    _subscription = null;
    _channel = null;
    _observerCount = 0;
    _intentionalClose = false;
    _reconnecting = false;
    _reconnectInterval = _defaultInterval;
    _apiGroupBaseUrl = null;
    _realtimeConnectionHash = null;
    _realtimeAuthToken = null;
  }

  /// Expose the current reconnect interval for test assertions.
  @visibleForTesting
  int get reconnectIntervalForTest => _reconnectInterval;

  /// Expose whether a reconnect is in progress for test assertions.
  @visibleForTesting
  bool get reconnectingForTest => _reconnecting;

  /// Expose observer count for test assertions.
  @visibleForTesting
  int get observerCountForTest => _observerCount;
}
