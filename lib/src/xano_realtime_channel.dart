import 'dart:async';
import 'dart:convert';

import 'xano_realtime_action.dart';
import 'xano_realtime_message.dart';
import 'xano_realtime_peer.dart';
import 'xano_realtime_state.dart';

// ── internal helpers ──────────────────────────────────────────────────────────

/// Equivalent to `realtimeBuildActionUtil` in the JS SDK.
/// Serialises `{ action, options, payload }` to a JSON string.
String _buildWireMessage(
  XanoRealtimeAction action,
  Map<String, dynamic> options, [
  dynamic payload,
]) {
  return jsonEncode({
    'action': action.wire,
    'options': options,
    'payload': payload,
  });
}

// ── listener bookkeeping ───────────────────────────────────────────────────────

typedef XanoMessageCallback = void Function(XanoRealtimeMessage message);
typedef XanoErrorCallback = void Function(XanoRealtimeMessage error);

class _Listener {
  final XanoRealtimeAction? action; // null → receive every action
  final XanoMessageCallback onMessage;
  final XanoErrorCallback? onError;

  const _Listener({
    required this.action,
    required this.onMessage,
    this.onError,
  });
}

// ── channel options ────────────────────────────────────────────────────────────

/// Options that mirror the second argument of `xano.channel(name, options)`.
class XanoChannelOptions {
  /// Request message history on join (channel must have history enabled).
  final bool history;

  /// Enable presence tracking for this channel.
  final bool presence;

  /// Queue messages sent while offline; flush them once reconnected.
  final bool queueOfflineActions;

  const XanoChannelOptions({
    this.history = false,
    this.presence = false,
    this.queueOfflineActions = false,
  });
}

// ── XanoRealtimeChannel ────────────────────────────────────────────────────────

/// A subscription to a single Xano realtime channel.
///
/// Obtain an instance via [XanoRealtimeClient.channel].
///
/// ## Lifecycle
/// 1. Construct via [XanoRealtimeClient.channel] — the WebSocket is opened
///    automatically when the first [on] listener is registered.
/// 2. Listen to events with [on].
/// 3. Send messages with [message].
/// 4. Call [destroy] when done to leave the channel and release resources.
///
/// ## Example
/// ```dart
/// final ch = client.channel('chat-room', presence: true);
///
/// // Listen to all events
/// ch.on(XanoRealtimeAction.message, (msg) {
///   print('Message: ${msg.payload}');
/// }, onError: (err) {
///   print('Error: ${err.payload}');
/// });
///
/// // Send a message to all connected clients
/// ch.message({'text': 'Hello, world!'});
///
/// // Send an authenticated-only message
/// ch.message({'text': 'Secret'}, authenticated: true);
///
/// // Clean up
/// ch.destroy();
/// ```
class XanoRealtimeChannel {
  /// The channel name as registered in the Xano dashboard.
  final String channel;

  final XanoChannelOptions _options;
  final XanoRealtimeState _state;

  final List<_Listener> _listeners = [];
  final List<String> _offlineQueue = [];
  final List<XanoRealtimePeer> _presenceCache = [];

  bool _observed = false;
  StreamSubscription<XanoRealtimeMessage>? _subscription;

  XanoRealtimeChannel(
    this.channel,
    this._options,
    this._state,
  );

  // ── public API ─────────────────────────────────────────────────────────────

  /// Register a listener for [action] events on this channel.
  ///
  /// - [action] — the event type to listen for. Pass `null` to receive every
  ///   action (wildcard).
  /// - [onMessage] — called with the parsed [XanoRealtimeMessage].
  /// - [onError] — optional; called when [XanoRealtimeAction.error] arrives
  ///   **and** [action] matches.
  ///
  /// Returns `this` for chaining.
  ///
  /// ```dart
  /// channel
  ///   .on(XanoRealtimeAction.message, (m) => print(m.payload))
  ///   .on(XanoRealtimeAction.connectionStatus, (m) => print(m.connectionStatus));
  /// ```
  XanoRealtimeChannel on(
    XanoRealtimeAction? action,
    XanoMessageCallback onMessage, {
    XanoErrorCallback? onError,
  }) {
    if (!_observed) {
      _startObserving();
      _observed = true;
    }
    _listeners.add(_Listener(
      action: action,
      onMessage: onMessage,
      onError: onError,
    ));
    return this;
  }

  /// Send a message to all clients in the channel.
  ///
  /// [payload] can be any JSON-serialisable value (Map, List, String, …).
  ///
  /// Set [authenticated] to `true` to restrict delivery to authenticated
  /// clients only (mirrors `{ authenticated: true }` in the JS SDK).
  ///
  /// If the socket is currently closed and [XanoChannelOptions.queueOfflineActions]
  /// is enabled, the message will be queued and sent once reconnected.
  void message(dynamic payload, {bool authenticated = false}) {
    final options = <String, dynamic>{
      'channel': channel,
      if (authenticated) 'authenticated': true,
    };
    final wire = _buildWireMessage(XanoRealtimeAction.message, options, payload);

    final socket = _state.socket;
    if (socket != null) {
      socket.sink.add(wire);
    } else if (_options.queueOfflineActions) {
      _offlineQueue.add(wire);
    }
  }

  /// Request the message history of this channel.
  ///
  /// The response arrives as a [XanoRealtimeAction.history] event on [on].
  /// History must be enabled on the channel in the Xano dashboard.
  void history() {
    final socket = _state.socket;
    if (socket == null) return;
    final wire = _buildWireMessage(
      XanoRealtimeAction.history,
      {'channel': channel},
    );
    socket.sink.add(wire);
  }

  /// Returns the current list of peers present in the channel.
  ///
  /// Only populated when [XanoChannelOptions.presence] was `true`.
  List<XanoRealtimePeer> getPresence() => List.unmodifiable(_presenceCache);

  /// Leave the channel and remove all listeners.
  ///
  /// If this was the last open channel, the underlying WebSocket is closed.
  void destroy() {
    final socket = _state.socket;
    if (socket != null) {
      final wire = _buildWireMessage(
        XanoRealtimeAction.leave,
        {'channel': channel},
      );
      socket.sink.add(wire);
    }
    _stopObserving();
  }

  // ── internal ───────────────────────────────────────────────────────────────

  void _startObserving() {
    _state.incrementObservers();
    _subscription = _state.messages.listen(_onMessage);

    // If the socket is already open (e.g. a second channel on an existing
    // connection), send the join frame now. The subscription is active so
    // the server's response (presence_full, history) will be received.
    if (_state.socket != null) {
      _handleConnectionUpdate(XanoRealtimeMessage(
        action: XanoRealtimeAction.connectionStatus,
        options: {},
        payload: {'status': XanoConnectionStatus.connected.wire},
      ));
    }
  }

  void _stopObserving() {
    _subscription?.cancel();
    _subscription = null;
    _listeners.clear();
    _presenceCache.clear();
    _observed = false;
    _state.decrementObservers();
  }

  void _onMessage(XanoRealtimeMessage msg) {
    // Filter: only handle messages for this channel or channel-less ones.
    final msgChannel = msg.options['channel'] as String?;
    if (msgChannel != null && msgChannel != channel) return;

    // Internal bookkeeping first.
    switch (msg.action) {
      case XanoRealtimeAction.connectionStatus:
        _handleConnectionUpdate(msg);
      case XanoRealtimeAction.presenceFull:
      case XanoRealtimeAction.presenceUpdate:
        _handlePresenceUpdate(msg);
      default:
        break;
    }

    // Dispatch to registered listeners.
    for (final listener in List.of(_listeners)) {
      // Wildcard listeners receive everything; typed listeners only their action.
      final matches = listener.action == null || listener.action == msg.action;
      if (!matches) continue;

      if (msg.action == XanoRealtimeAction.error && listener.onError != null) {
        listener.onError!.call(msg);
      } else {
        listener.onMessage(msg);
      }
    }
  }

  void _handleConnectionUpdate(XanoRealtimeMessage msg) {
    if (msg.connectionStatus == XanoConnectionStatus.connected) {
      final socket = _state.socket;
      if (socket == null) return;
      // Send the join frame -- equivalent to handleConnectionUpdate in JS SDK.
      final wire = _buildWireMessage(
        XanoRealtimeAction.join,
        {'channel': channel},
        {
          'history': _options.history,
          'presence': _options.presence,
        },
      );
      socket.sink.add(wire);

      // Flush queued messages after the join frame (only on connected).
      _flushOfflineQueue();
    }
  }

  void _handlePresenceUpdate(XanoRealtimeMessage msg) {
    if (msg.action == XanoRealtimeAction.presenceFull) {
      // Full snapshot — replace cache.
      final presence = (msg.payload?['presence'] as List?) ?? [];
      _presenceCache
        ..clear()
        ..addAll(presence
            .whereType<Map>()
            .map((e) => XanoRealtimePeer(
                  socketId: e['socketId'] as String? ?? '',
                  raw: Map<String, dynamic>.from(e),
                  channel: channel,
                )));
    } else if (msg.action == XanoRealtimeAction.presenceUpdate) {
      final subAction = XanoPresenceAction.fromWire(
        (msg.payload?['action'] as String?) ?? '',
      );
      final peerData = (msg.payload?['presence'] as Map?)
          ?.cast<String, dynamic>();
      if (peerData == null) return;
      final socketId = peerData['socketId'] as String? ?? '';

      if (subAction == XanoPresenceAction.join) {
        _presenceCache.add(XanoRealtimePeer(
          socketId: socketId,
          raw: peerData,
          channel: channel,
        ));
      } else if (subAction == XanoPresenceAction.leave) {
        _presenceCache.removeWhere((p) => p.socketId == socketId);
      }
    }
  }

  void _flushOfflineQueue() {
    if (!_options.queueOfflineActions) return;
    final socket = _state.socket;
    if (socket == null) return;
    while (_offlineQueue.isNotEmpty) {
      socket.sink.add(_offlineQueue.removeAt(0));
    }
  }
}
