/// Mirrors `ERealtimeAction` from the Xano JS SDK.
///
/// These are the `action` values that arrive on the WebSocket wire and
/// are also used when subscribing with [XanoRealtimeChannel.on].
enum XanoRealtimeAction {
  /// The WebSocket connection opened or closed.
  connectionStatus('connection_status'),

  /// An error occurred on the channel or connection.
  error('error'),

  /// A custom server-side event fired by a Realtime Trigger.
  event('event'),

  /// Historical messages returned after [XanoRealtimeChannel.history] call.
  history('history'),

  /// A client joined the channel (presence).
  join('join'),

  /// A client left the channel (presence).
  leave('leave'),

  /// A public or private message sent to the channel.
  message('message'),

  /// Full snapshot of all present clients (received on join when presence=true).
  presenceFull('presence_full'),

  /// Incremental presence update (join/leave of a single client).
  presenceUpdate('presence_update');

  const XanoRealtimeAction(this.wire);

  /// The raw string used on the WebSocket wire.
  final String wire;

  static XanoRealtimeAction? fromWire(String value) {
    for (final a in values) {
      if (a.wire == value) return a;
    }
    return null;
  }
}

/// Connection status values inside a [XanoRealtimeAction.connectionStatus] message.
enum XanoConnectionStatus {
  connected('connected'),
  disconnected('disconnected');

  const XanoConnectionStatus(this.wire);
  final String wire;

  static XanoConnectionStatus? fromWire(String v) {
    for (final s in values) {
      if (s.wire == v) return s;
    }
    return null;
  }
}

/// Presence sub-action values inside [XanoRealtimeAction.presenceUpdate].
enum XanoPresenceAction {
  join('join'),
  leave('leave');

  const XanoPresenceAction(this.wire);
  final String wire;

  static XanoPresenceAction? fromWire(String v) {
    for (final a in values) {
      if (a.wire == v) return a;
    }
    return null;
  }
}
