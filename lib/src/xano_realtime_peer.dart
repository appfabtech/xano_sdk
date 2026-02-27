import 'dart:convert';

import 'xano_realtime_action.dart';
import 'xano_realtime_state.dart';

/// Represents another client currently present in a channel.
///
/// Mirrors `XanoRealtimeClient` in the JS SDK. Obtained via
/// [XanoRealtimeChannel.getPresence].
class XanoRealtimePeer {
  /// The socket ID assigned by the server to this peer.
  final String socketId;

  /// Any additional metadata the server exposes for this peer.
  final Map<String, dynamic> data;

  /// Reference back to the channel name -- needed to address private messages.
  final String _channel;

  XanoRealtimePeer({
    required this.socketId,
    required Map<String, dynamic> raw,
    required String channel,
  })  : data = raw,
        _channel = channel;

  /// Send a private message directly to this peer.
  ///
  /// Equivalent to `client.message(payload)` in the JS SDK.
  void message(dynamic payload) {
    final socket = XanoRealtimeState.instance.socket;
    if (socket == null) return;
    final wire = jsonEncode({
      'action': XanoRealtimeAction.message.wire,
      'options': {
        'channel': _channel,
        'socketId': socketId,
      },
      'payload': payload,
    });
    socket.sink.add(wire);
  }

  /// Request the history of the channel.
  void history() {
    final socket = XanoRealtimeState.instance.socket;
    if (socket == null) return;
    final wire = jsonEncode({
      'action': XanoRealtimeAction.history.wire,
      'options': {
        'channel': _channel,
      },
      'payload': null,
    });
    socket.sink.add(wire);
  }

  @override
  String toString() => 'XanoRealtimePeer(socketId: $socketId)';
}
