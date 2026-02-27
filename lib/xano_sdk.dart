/// Flutter port of the Xano JS SDK — realtime WebSocket channels only.
///
/// ## Quick start
/// ```dart
/// final client = XanoRealtimeClient(
///   apiGroupBaseUrl: 'https://x8ki-letl-twmt.n7.xano.io/api:jVuUQATw',
///   realtimeConnectionHash: 'YOUR_CONNECTION_HASH',
/// );
///
/// final channel = client.channel('my-channel', presence: true);
///
/// channel.on(XanoRealtimeAction.message, (msg) => print(msg.payload));
/// channel.message({'text': 'Hello!'});
///
/// // Clean up
/// channel.destroy();
/// client.disconnect();
/// ```
library xano_sdk;

export 'src/xano_realtime_action.dart';
export 'src/xano_realtime_client.dart';
export 'src/xano_realtime_channel.dart';
export 'src/xano_realtime_message.dart';
export 'src/xano_realtime_peer.dart';
