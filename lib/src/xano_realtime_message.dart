import 'xano_realtime_action.dart';

/// Typed envelope for every message received from the Xano realtime server.
///
/// Mirrors the raw JSON shape: `{ action, options, payload }`.
class XanoRealtimeMessage {
  /// The action that describes what this message represents.
  final XanoRealtimeAction action;

  /// Channel-scoped options included by the server (e.g. `{channel: "room1"}`).
  final Map<String, dynamic> options;

  /// The actual data payload. Its shape varies by [action]:
  /// - `message`         → whatever the sender passed
  /// - `connectionStatus`→ `{status: "connected" | "disconnected"}`
  /// - `presenceFull`    → `{presence: [...]}`
  /// - `presenceUpdate`  → `{action: "join"|"leave", presence: {...}}`
  /// - `history`         → list of historic messages
  /// - `error`           → error details from the server
  final dynamic payload;

  /// Optional client descriptor for peer-to-peer messages.
  final Map<String, dynamic>? client;

  const XanoRealtimeMessage({
    required this.action,
    required this.options,
    required this.payload,
    this.client,
  });

  factory XanoRealtimeMessage.fromJson(Map<String, dynamic> json) {
    final actionStr = json['action'] as String? ?? '';
    final action = XanoRealtimeAction.fromWire(actionStr)
        ?? XanoRealtimeAction.event; // fall back to event for unknown actions
    return XanoRealtimeMessage(
      action: action,
      options: (json['options'] as Map?)?.cast<String, dynamic>() ?? {},
      payload: json['payload'],
      client: (json['client'] as Map?)?.cast<String, dynamic>(),
    );
  }

  /// Convenience: returns the connection status when action == connectionStatus.
  XanoConnectionStatus? get connectionStatus {
    if (action != XanoRealtimeAction.connectionStatus) return null;
    final status = (payload as Map?)?['status'] as String?;
    return status != null ? XanoConnectionStatus.fromWire(status) : null;
  }

  @override
  String toString() =>
      'XanoRealtimeMessage(action: ${action.wire}, payload: $payload)';
}
