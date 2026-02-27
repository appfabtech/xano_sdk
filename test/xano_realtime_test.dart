import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:xano_sdk/xano_sdk.dart';
import 'package:xano_sdk/src/xano_realtime_state.dart';

void main() {
  // ── XanoRealtimeAction ────────────────────────────────────────────────────
  group('XanoRealtimeAction', () {
    test('fromWire returns correct enum for every known wire value', () {
      final cases = {
        'connection_status': XanoRealtimeAction.connectionStatus,
        'error': XanoRealtimeAction.error,
        'event': XanoRealtimeAction.event,
        'history': XanoRealtimeAction.history,
        'join': XanoRealtimeAction.join,
        'leave': XanoRealtimeAction.leave,
        'message': XanoRealtimeAction.message,
        'presence_full': XanoRealtimeAction.presenceFull,
        'presence_update': XanoRealtimeAction.presenceUpdate,
      };
      for (final entry in cases.entries) {
        expect(
          XanoRealtimeAction.fromWire(entry.key),
          entry.value,
          reason: 'wire="${entry.key}"',
        );
      }
    });

    test('fromWire returns null for unknown wire value', () {
      expect(XanoRealtimeAction.fromWire('unknown_action'), isNull);
    });

    test('wire property round-trips through fromWire', () {
      for (final action in XanoRealtimeAction.values) {
        expect(XanoRealtimeAction.fromWire(action.wire), action);
      }
    });
  });

  // ── XanoConnectionStatus ──────────────────────────────────────────────────
  group('XanoConnectionStatus', () {
    test('fromWire parses connected / disconnected', () {
      expect(
        XanoConnectionStatus.fromWire('connected'),
        XanoConnectionStatus.connected,
      );
      expect(
        XanoConnectionStatus.fromWire('disconnected'),
        XanoConnectionStatus.disconnected,
      );
      expect(XanoConnectionStatus.fromWire('other'), isNull);
    });
  });

  // ── XanoRealtimeMessage ───────────────────────────────────────────────────
  group('XanoRealtimeMessage', () {
    test('fromJson parses a standard message frame', () {
      final json = {
        'action': 'message',
        'options': {'channel': 'chat-room'},
        'payload': {'text': 'Hello!'},
      };
      final msg = XanoRealtimeMessage.fromJson(json);

      expect(msg.action, XanoRealtimeAction.message);
      expect(msg.options['channel'], 'chat-room');
      expect((msg.payload as Map)['text'], 'Hello!');
      expect(msg.client, isNull);
    });

    test('fromJson parses a connection_status frame', () {
      final json = {
        'action': 'connection_status',
        'options': {},
        'payload': {'status': 'connected'},
      };
      final msg = XanoRealtimeMessage.fromJson(json);

      expect(msg.action, XanoRealtimeAction.connectionStatus);
      expect(msg.connectionStatus, XanoConnectionStatus.connected);
    });

    test('fromJson falls back to event for unknown action', () {
      final json = {
        'action': 'totally_unknown',
        'options': {},
        'payload': null,
      };
      final msg = XanoRealtimeMessage.fromJson(json);
      expect(msg.action, XanoRealtimeAction.event);
    });

    test('connectionStatus returns null for non-connectionStatus messages', () {
      final msg = XanoRealtimeMessage(
        action: XanoRealtimeAction.message,
        options: {},
        payload: 'hi',
      );
      expect(msg.connectionStatus, isNull);
    });

    test('fromJson handles missing options and payload gracefully', () {
      final json = {'action': 'join'};
      final msg = XanoRealtimeMessage.fromJson(json);
      expect(msg.action, XanoRealtimeAction.join);
      expect(msg.options, isEmpty);
      expect(msg.payload, isNull);
    });

    test('fromJson parses client field', () {
      final json = {
        'action': 'message',
        'options': {},
        'payload': 'hi',
        'client': {'socketId': 'abc123', 'userId': 42},
      };
      final msg = XanoRealtimeMessage.fromJson(json);
      expect(msg.client?['socketId'], 'abc123');
    });
  });

  // ── XanoPresenceAction ───────────────────────────────────────────────────
  group('XanoPresenceAction', () {
    test('fromWire parses join and leave', () {
      expect(XanoPresenceAction.fromWire('join'), XanoPresenceAction.join);
      expect(XanoPresenceAction.fromWire('leave'), XanoPresenceAction.leave);
      expect(XanoPresenceAction.fromWire('other'), isNull);
    });
  });

  // ── XanoChannelOptions ───────────────────────────────────────────────────
  group('XanoChannelOptions', () {
    test('defaults are all false', () {
      const opts = XanoChannelOptions();
      expect(opts.history, isFalse);
      expect(opts.presence, isFalse);
      expect(opts.queueOfflineActions, isFalse);
    });

    test('custom values are preserved', () {
      const opts = XanoChannelOptions(
        history: true,
        presence: true,
        queueOfflineActions: true,
      );
      expect(opts.history, isTrue);
      expect(opts.presence, isTrue);
      expect(opts.queueOfflineActions, isTrue);
    });
  });

  // ── XanoRealtimeClient ───────────────────────────────────────────────────
  group('XanoRealtimeClient', () {
    late XanoRealtimeState state;

    setUp(() {
      state = XanoRealtimeState.instance;
      state.resetForTest();
    });

    tearDown(() {
      state.resetForTest();
    });

    test('hasRealtimeAuthToken reflects constructor argument', () {
      final clientWithToken = XanoRealtimeClient(
        apiGroupBaseUrl: 'https://example.n7.xano.io/api:abc',
        realtimeConnectionHash: 'hash123',
        realtimeAuthToken: 'mytoken',
      );
      expect(clientWithToken.hasRealtimeAuthToken, isTrue);

      state.resetForTest();

      final clientWithout = XanoRealtimeClient(
        apiGroupBaseUrl: 'https://example.n7.xano.io/api:abc',
        realtimeConnectionHash: 'hash123',
      );
      expect(clientWithout.hasRealtimeAuthToken, isFalse);
    });

    test('channel() returns a XanoRealtimeChannel', () {
      final client = XanoRealtimeClient(
        apiGroupBaseUrl: 'https://example.n7.xano.io/api:abc',
        realtimeConnectionHash: 'hash123',
      );
      final ch = client.channel('room1');
      expect(ch, isA<XanoRealtimeChannel>());
      expect(ch.channel, 'room1');
    });

    test('channel() with options creates channel with correct settings', () {
      final client = XanoRealtimeClient(
        apiGroupBaseUrl: 'https://example.n7.xano.io/api:abc',
        realtimeConnectionHash: 'hash123',
      );
      final ch = client.channel(
        'presence-room',
        presence: true,
        history: true,
        queueOfflineActions: true,
      );
      expect(ch.channel, 'presence-room');
    });
  });

  // ── XanoRealtimeChannel — presence cache ─────────────────────────────────
  group('XanoRealtimeChannel.getPresence', () {
    late XanoRealtimeState state;

    setUp(() {
      state = XanoRealtimeState.instance;
      state.resetForTest();
    });

    tearDown(() {
      state.resetForTest();
    });

    test('returns empty list before any presence event', () {
      final client = XanoRealtimeClient(
        apiGroupBaseUrl: 'https://example.n7.xano.io/api:abc',
        realtimeConnectionHash: 'hash123',
      );
      final ch = client.channel('room', presence: true);
      expect(ch.getPresence(), isEmpty);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // BEHAVIORAL TESTS
  // ══════════════════════════════════════════════════════════════════════════

  group('Behavioral: presence cache', () {
    late XanoRealtimeState state;
    late XanoRealtimeClient client;
    late XanoRealtimeChannel channel;

    setUp(() {
      state = XanoRealtimeState.instance;
      state.resetForTest();
      client = XanoRealtimeClient(
        apiGroupBaseUrl: 'https://example.n7.xano.io/api:abc',
        realtimeConnectionHash: 'hash123',
      );
      channel = client.channel('test-room', presence: true);
    });

    tearDown(() {
      state.resetForTest();
    });

    test('presenceFull replaces the entire cache', () async {
      // Register a listener to activate the subscription.
      final completer = Completer<void>();
      channel.on(XanoRealtimeAction.presenceFull, (_) {
        if (!completer.isCompleted) completer.complete();
      });

      // Emit a presenceFull message.
      state.emitForTest(XanoRealtimeMessage(
        action: XanoRealtimeAction.presenceFull,
        options: {'channel': 'test-room'},
        payload: {
          'presence': [
            {'socketId': 'a1', 'name': 'Alice'},
            {'socketId': 'b2', 'name': 'Bob'},
          ]
        },
      ));

      await completer.future;
      final peers = channel.getPresence();
      expect(peers, hasLength(2));
      expect(peers[0].socketId, 'a1');
      expect(peers[1].socketId, 'b2');
    });

    test('presenceUpdate join adds a peer', () async {
      final completer = Completer<void>();
      channel.on(XanoRealtimeAction.presenceUpdate, (_) {
        if (!completer.isCompleted) completer.complete();
      });

      state.emitForTest(XanoRealtimeMessage(
        action: XanoRealtimeAction.presenceUpdate,
        options: {'channel': 'test-room'},
        payload: {
          'action': 'join',
          'presence': {'socketId': 'c3', 'name': 'Charlie'},
        },
      ));

      await completer.future;
      final peers = channel.getPresence();
      expect(peers, hasLength(1));
      expect(peers[0].socketId, 'c3');
    });

    test('presenceUpdate leave removes a peer', () async {
      // Seed the cache with a presenceFull.
      final fullCompleter = Completer<void>();
      channel.on(XanoRealtimeAction.presenceFull, (_) {
        if (!fullCompleter.isCompleted) fullCompleter.complete();
      });

      state.emitForTest(XanoRealtimeMessage(
        action: XanoRealtimeAction.presenceFull,
        options: {'channel': 'test-room'},
        payload: {
          'presence': [
            {'socketId': 'a1', 'name': 'Alice'},
            {'socketId': 'b2', 'name': 'Bob'},
          ]
        },
      ));
      await fullCompleter.future;
      expect(channel.getPresence(), hasLength(2));

      // Now emit a leave.
      final leaveCompleter = Completer<void>();
      channel.on(XanoRealtimeAction.presenceUpdate, (_) {
        if (!leaveCompleter.isCompleted) leaveCompleter.complete();
      });

      state.emitForTest(XanoRealtimeMessage(
        action: XanoRealtimeAction.presenceUpdate,
        options: {'channel': 'test-room'},
        payload: {
          'action': 'leave',
          'presence': {'socketId': 'a1'},
        },
      ));
      await leaveCompleter.future;
      final peers = channel.getPresence();
      expect(peers, hasLength(1));
      expect(peers[0].socketId, 'b2');
    });
  });

  group('Behavioral: channel message filtering', () {
    late XanoRealtimeState state;
    late XanoRealtimeClient client;

    setUp(() {
      state = XanoRealtimeState.instance;
      state.resetForTest();
      client = XanoRealtimeClient(
        apiGroupBaseUrl: 'https://example.n7.xano.io/api:abc',
        realtimeConnectionHash: 'hash123',
      );
    });

    tearDown(() {
      state.resetForTest();
    });

    test('channel only receives messages for its own channel name', () async {
      final ch1 = client.channel('room-a');
      final ch2 = client.channel('room-b');

      final ch1Messages = <String>[];
      final ch2Messages = <String>[];

      final c1 = Completer<void>();
      final c2 = Completer<void>();

      ch1.on(XanoRealtimeAction.message, (msg) {
        ch1Messages.add(msg.payload.toString());
        if (!c1.isCompleted) c1.complete();
      });

      ch2.on(XanoRealtimeAction.message, (msg) {
        ch2Messages.add(msg.payload.toString());
        if (!c2.isCompleted) c2.complete();
      });

      // Message for room-a.
      state.emitForTest(XanoRealtimeMessage(
        action: XanoRealtimeAction.message,
        options: {'channel': 'room-a'},
        payload: 'hello-a',
      ));

      // Message for room-b.
      state.emitForTest(XanoRealtimeMessage(
        action: XanoRealtimeAction.message,
        options: {'channel': 'room-b'},
        payload: 'hello-b',
      ));

      await c1.future;
      await c2.future;

      expect(ch1Messages, ['hello-a']);
      expect(ch2Messages, ['hello-b']);
    });

    test('channel-less messages are received by all channels', () async {
      final ch = client.channel('any-room');
      final received = <XanoRealtimeAction>[];

      final completer = Completer<void>();
      ch.on(null, (msg) {
        received.add(msg.action);
        if (!completer.isCompleted) completer.complete();
      });

      // A connectionStatus message has no channel in options.
      state.emitForTest(XanoRealtimeMessage(
        action: XanoRealtimeAction.connectionStatus,
        options: {},
        payload: {'status': 'disconnected'},
      ));

      await completer.future;
      expect(received, contains(XanoRealtimeAction.connectionStatus));
    });
  });

  group('Behavioral: error dispatch', () {
    late XanoRealtimeState state;
    late XanoRealtimeClient client;

    setUp(() {
      state = XanoRealtimeState.instance;
      state.resetForTest();
      client = XanoRealtimeClient(
        apiGroupBaseUrl: 'https://example.n7.xano.io/api:abc',
        realtimeConnectionHash: 'hash123',
      );
    });

    tearDown(() {
      state.resetForTest();
    });

    test('error goes to onError when provided', () async {
      final ch = client.channel('err-room');
      XanoRealtimeMessage? errorMsg;
      XanoRealtimeMessage? normalMsg;

      final completer = Completer<void>();
      ch.on(XanoRealtimeAction.error, (msg) {
        normalMsg = msg;
      }, onError: (msg) {
        errorMsg = msg;
        if (!completer.isCompleted) completer.complete();
      });

      state.emitForTest(XanoRealtimeMessage(
        action: XanoRealtimeAction.error,
        options: {'channel': 'err-room'},
        payload: 'something went wrong',
      ));

      await completer.future;
      expect(errorMsg, isNotNull);
      expect(errorMsg!.payload, 'something went wrong');
      expect(normalMsg, isNull);
    });

    test('error falls through to onMessage when onError is not provided',
        () async {
      final ch = client.channel('err-room');
      XanoRealtimeMessage? receivedMsg;

      final completer = Completer<void>();
      ch.on(XanoRealtimeAction.error, (msg) {
        receivedMsg = msg;
        if (!completer.isCompleted) completer.complete();
      });

      state.emitForTest(XanoRealtimeMessage(
        action: XanoRealtimeAction.error,
        options: {'channel': 'err-room'},
        payload: 'fallback error',
      ));

      await completer.future;
      expect(receivedMsg, isNotNull);
      expect(receivedMsg!.payload, 'fallback error');
    });

    test('wildcard listener receives errors via onMessage when no onError',
        () async {
      final ch = client.channel('err-room');
      final received = <XanoRealtimeAction>[];

      final completer = Completer<void>();
      ch.on(null, (msg) {
        received.add(msg.action);
        if (msg.action == XanoRealtimeAction.error && !completer.isCompleted) {
          completer.complete();
        }
      });

      state.emitForTest(XanoRealtimeMessage(
        action: XanoRealtimeAction.error,
        options: {'channel': 'err-room'},
        payload: 'wildcard error',
      ));

      await completer.future;
      expect(received, contains(XanoRealtimeAction.error));
    });
  });

  group('Behavioral: observer count', () {
    late XanoRealtimeState state;

    setUp(() {
      state = XanoRealtimeState.instance;
      state.resetForTest();
      state.configure(
        apiGroupBaseUrl: 'https://example.n7.xano.io/api:abc',
        realtimeConnectionHash: 'hash123',
      );
    });

    tearDown(() {
      state.resetForTest();
    });

    test('incrementObservers increases and decrementObservers decreases', () {
      state.incrementObservers();
      expect(state.observerCountForTest, 1);
      state.incrementObservers();
      expect(state.observerCountForTest, 2);
      state.decrementObservers();
      expect(state.observerCountForTest, 1);
      state.decrementObservers();
      expect(state.observerCountForTest, 0);
    });

    test('decrementObservers does not go below zero', () {
      expect(state.observerCountForTest, 0);
      state.decrementObservers();
      expect(state.observerCountForTest, 0);
      state.decrementObservers();
      expect(state.observerCountForTest, 0);
    });
  });

  group('Behavioral: singleton reconfiguration guard', () {
    late XanoRealtimeState state;

    setUp(() {
      state = XanoRealtimeState.instance;
      state.resetForTest();
    });

    tearDown(() {
      state.resetForTest();
    });

    test('configure allows same config when no socket', () {
      // No socket open, so configure should not throw.
      state.configure(
        apiGroupBaseUrl: 'https://a.xano.io/api:abc',
        realtimeConnectionHash: 'hash1',
      );
      state.configure(
        apiGroupBaseUrl: 'https://b.xano.io/api:def',
        realtimeConnectionHash: 'hash2',
      );
      // No exception means pass.
    });
  });

  group('Behavioral: setRealtimeAuthToken', () {
    late XanoRealtimeState state;

    setUp(() {
      state = XanoRealtimeState.instance;
      state.resetForTest();
    });

    tearDown(() {
      state.resetForTest();
    });

    test('client exposes setRealtimeAuthToken', () {
      final client = XanoRealtimeClient(
        apiGroupBaseUrl: 'https://example.n7.xano.io/api:abc',
        realtimeConnectionHash: 'hash123',
      );
      expect(client.hasRealtimeAuthToken, isFalse);
      // Setting the token via the client method should not throw.
      client.setRealtimeAuthToken('new-token');
    });
  });

  group('Behavioral: destroy cleans up', () {
    late XanoRealtimeState state;
    late XanoRealtimeClient client;

    setUp(() {
      state = XanoRealtimeState.instance;
      state.resetForTest();
      client = XanoRealtimeClient(
        apiGroupBaseUrl: 'https://example.n7.xano.io/api:abc',
        realtimeConnectionHash: 'hash123',
      );
    });

    tearDown(() {
      state.resetForTest();
    });

    test('destroy clears listeners and presence cache', () async {
      final ch = client.channel('room', presence: true);

      final completer = Completer<void>();
      ch.on(XanoRealtimeAction.presenceFull, (_) {
        if (!completer.isCompleted) completer.complete();
      });

      // Populate presence.
      state.emitForTest(XanoRealtimeMessage(
        action: XanoRealtimeAction.presenceFull,
        options: {'channel': 'room'},
        payload: {
          'presence': [
            {'socketId': 'x1', 'name': 'Xena'},
          ]
        },
      ));
      await completer.future;
      expect(ch.getPresence(), hasLength(1));

      // Destroy should clear everything.
      ch.destroy();
      expect(ch.getPresence(), isEmpty);
    });

    test('messages after destroy are not received', () async {
      final ch = client.channel('room');
      final messages = <String>[];

      final completer = Completer<void>();
      ch.on(XanoRealtimeAction.message, (msg) {
        messages.add(msg.payload.toString());
        if (!completer.isCompleted) completer.complete();
      });

      // First message should arrive.
      state.emitForTest(XanoRealtimeMessage(
        action: XanoRealtimeAction.message,
        options: {'channel': 'room'},
        payload: 'before-destroy',
      ));
      await completer.future;
      expect(messages, ['before-destroy']);

      // Destroy, then emit another message.
      ch.destroy();
      state.emitForTest(XanoRealtimeMessage(
        action: XanoRealtimeAction.message,
        options: {'channel': 'room'},
        payload: 'after-destroy',
      ));

      // Give the event loop a chance to process.
      await Future.delayed(Duration.zero);
      expect(messages, ['before-destroy']);
    });
  });
}
