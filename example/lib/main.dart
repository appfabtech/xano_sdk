import 'package:flutter/material.dart';
import 'package:xano_sdk/xano_sdk.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CONFIGURATION
// Copy env.example.dart to env.dart and fill in your Xano values.
// env.dart is gitignored so your credentials stay local.
// ─────────────────────────────────────────────────────────────────────────────
import 'env.dart' as env;

const _apiGroupBaseUrl = env.xanoBaseUrl;
const _connectionHash = env.xanoConnectionHash;
const _channelName = env.xanoChannel;

// Optional: set a JWT to connect as an authenticated user.
const _authToken = null; // e.g. 'eyJhbGci...'
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  runApp(const XanoExampleApp());
}

class XanoExampleApp extends StatelessWidget {
  const XanoExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Xano Realtime Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF5B4CF5)),
        useMaterial3: true,
      ),
      home: const ChatPage(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Chat page
// ─────────────────────────────────────────────────────────────────────────────

class _ChatEntry {
  final String text;
  final bool isSystem;
  final bool isMine;
  final bool isServerEvent;

  _ChatEntry({
    required this.text,
    this.isSystem = false,
    this.isMine = false,
    this.isServerEvent = false,
  });
}

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  late final XanoRealtimeClient _client;
  late final XanoRealtimeChannel _channel;

  final List<_ChatEntry> _messages = [];
  final Set<String> _pendingSent = {};
  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();

  String _connectionStatus = 'Disconnected';
  int _presenceCount = 0;

  @override
  void initState() {
    super.initState();
    _initRealtime();
  }

  void _initRealtime() {
    _client = XanoRealtimeClient(
      apiGroupBaseUrl: _apiGroupBaseUrl,
      realtimeConnectionHash: _connectionHash,
      realtimeAuthToken: _authToken,
    );

    _channel = _client.channel(
      _channelName,
      presence: true,
      history: true,
      queueOfflineActions: true,
    );

    // ── connection status ──────────────────────────────────────────────────
    _channel.on(XanoRealtimeAction.connectionStatus, (msg) {
      final status = msg.connectionStatus;
      setState(() {
        _connectionStatus = status == XanoConnectionStatus.connected
            ? 'Connected ✅'
            : 'Reconnecting…';
        if (status == XanoConnectionStatus.connected) {
          _addSystem('Connected to "$_channelName"');
        } else {
          _addSystem('Disconnected — reconnecting…');
        }
      });
    });

    // ── incoming messages ──────────────────────────────────────────────────
    _channel.on(XanoRealtimeAction.message, (msg) {
      final payload = msg.payload;
      final text = payload is Map
          ? payload['text']?.toString() ?? payload.toString()
          : payload.toString();
      final isMine = _pendingSent.remove(text);
      setState(() => _messages.add(_ChatEntry(text: text, isMine: isMine)));
      _scrollToBottom();
    }, onError: (err) {
      _addSystem('Error: ${err.payload}');
    });

    // ── history ───────────────────────────────────────────────────────────
    _channel.on(XanoRealtimeAction.history, (msg) {
      final items = msg.payload;
      if (items is List) {
        setState(() {
          _addSystem('── History (${items.length} messages) ──');
          for (final item in items) {
            String text;
            if (item is Map) {
              final payload = item['payload'];
              text = (payload is Map ? payload['text']?.toString() : null) ??
                  item.toString();
            } else {
              text = item.toString();
            }
            _messages.add(_ChatEntry(text: text));
          }
        });
        _scrollToBottom();
      }
    });

    // ── presence ──────────────────────────────────────────────────────────
    _channel.on(XanoRealtimeAction.presenceFull, (msg) {
      setState(() {
        _presenceCount = _channel.getPresence().length;
        _addSystem('$_presenceCount user(s) online');
      });
    });

    _channel.on(XanoRealtimeAction.presenceUpdate, (msg) {
      final action = (msg.payload as Map?)?['action'] as String?;
      setState(() {
        _presenceCount = _channel.getPresence().length;
        _addSystem(action == 'join'
            ? 'A user joined ($_presenceCount online)'
            : 'A user left ($_presenceCount online)');
      });
    });

    // ── custom server events (from api.realtime_event) ────────────────────
    _channel.on(XanoRealtimeAction.event, (msg) {
      final payload = msg.payload;
      final text = payload is Map
          ? payload['data']?.toString() ?? payload.toString()
          : payload.toString();
      setState(() {
        _messages.add(_ChatEntry(text: text, isServerEvent: true));
      });
      _scrollToBottom();
    });
  }

  void _addSystem(String text) {
    _messages.add(_ChatEntry(text: text, isSystem: true));
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _sendMessage() {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;

    _pendingSent.add(text);
    _channel.message({'text': text});

    setState(() {
      _messages.add(_ChatEntry(text: text, isMine: true));
      _inputCtrl.clear();
    });
    _scrollToBottom();
  }

  void _requestHistory() => _channel.history();

  void _reconnect() {
    _addSystem('Forcing reconnect…');
    _client.reconnect();
  }

  @override
  void dispose() {
    _channel.destroy();
    _client.disconnect();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ── UI ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_channelName,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            Text(
              '$_connectionStatus  •  $_presenceCount online',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Request history',
            onPressed: _requestHistory,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Force reconnect',
            onPressed: _reconnect,
          ),
        ],
      ),
      body: Column(
        children: [
          // ── message list ──────────────────────────────────────────────
          Expanded(
            child: ListView.builder(
              controller: _scrollCtrl,
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _messages.length,
              itemBuilder: (_, i) => _MessageBubble(entry: _messages[i]),
            ),
          ),

          // ── input bar ─────────────────────────────────────────────────
          SafeArea(
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 4,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputCtrl,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendMessage(),
                      decoration: InputDecoration(
                        hintText: 'Type a message…',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: colorScheme.surfaceVariant,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _sendMessage,
                    style: FilledButton.styleFrom(
                      shape: const CircleBorder(),
                      padding: const EdgeInsets.all(14),
                    ),
                    child: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Message bubble widget
// ─────────────────────────────────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  final _ChatEntry entry;
  const _MessageBubble({required this.entry});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // System message (centred, muted)
    if (entry.isSystem) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
        child: Center(
          child: Text(
            entry.text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: cs.onSurface.withOpacity(0.5),
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      );
    }

    // Server event bubble (centred, accent color)
    if (entry.isServerEvent) {
      return Align(
        alignment: Alignment.center,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 32, vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: cs.tertiaryContainer,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cs.tertiary.withOpacity(0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cell_tower, size: 16, color: cs.onTertiaryContainer),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  entry.text,
                  style: TextStyle(color: cs.onTertiaryContainer),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Chat bubble (right = mine, left = theirs)
    final isMine = entry.isMine;
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.fromLTRB(
          isMine ? 64 : 12,
          3,
          isMine ? 12 : 64,
          3,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isMine ? cs.primary : cs.secondaryContainer,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isMine ? 18 : 4),
            bottomRight: Radius.circular(isMine ? 4 : 18),
          ),
        ),
        child: Text(
          entry.text,
          style: TextStyle(
            color: isMine ? cs.onPrimary : cs.onSecondaryContainer,
          ),
        ),
      ),
    );
  }
}
