import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

/// A single frame delivered by the SoftBase realtime channel.
class SoftBaseEvent {
  final String id;
  final String type;
  final String title;
  final String body;
  final bool loud;
  final Map<String, dynamic> data;
  final int? ts;

  const SoftBaseEvent({
    required this.id,
    required this.type,
    this.title = '',
    this.body = '',
    this.loud = false,
    this.data = const {},
    this.ts,
  });

  factory SoftBaseEvent.fromJson(Map<String, dynamic> json) {
    final dataRaw = json['data'];
    return SoftBaseEvent(
      id: json['id']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      body: json['body']?.toString() ?? '',
      loud: json['loud'] == true,
      data: dataRaw is Map
          ? Map<String, dynamic>.from(dataRaw)
          : const <String, dynamic>{},
      ts: json['ts'] is int ? json['ts'] as int : int.tryParse('${json['ts']}'),
    );
  }
}

/// Self-hosted "SoftBase" push channel: a single long-lived SSE connection
/// (`GET /realtime/softbase/stream?token=<mobileBearerToken>`) that delivers
/// instant frames such as VOIP_RING while the app is foregrounded or the
/// engine is alive in the background.
///
/// Reconnects automatically with a 5s → 60s exponential backoff that resets
/// after a healthy stretch of streaming. Frames are exposed on a broadcast
/// [stream]; connect/disconnect follow login/logout and app resume.
class SoftBaseService {
  SoftBaseService._();

  static final SoftBaseService instance = SoftBaseService._();

  static const _base = 'https://softcarshuttle.com';
  static const _minBackoff = Duration(seconds: 5);
  static const _maxBackoff = Duration(seconds: 60);
  static const _healthyAfter = Duration(seconds: 30);

  http.Client? _client;
  StreamSubscription<List<int>>? _subscription;
  Timer? _reconnectTimer;
  String? _token;
  bool _disposed = false;
  DateTime? _connectedAt;
  Duration _backoff = _minBackoff;

  /// Deduplicated event ids — bounded LRU-style set of 200.
  final Set<String> _seenEventIds = {};
  static const int _maxSeenIds = 200;

  final StreamController<SoftBaseEvent> _events =
      StreamController<SoftBaseEvent>.broadcast();

  /// Connection state broadcast: 'connected' | 'disconnected' | 'reconnecting'.
  final StreamController<String> _connStateController =
      StreamController<String>.broadcast();
  Stream<String> get connectionState => _connStateController.stream;
  String _connState = 'disconnected';

  /// All parsed SoftBase frames. Broadcast — multiple listeners allowed.
  Stream<SoftBaseEvent> get stream => _events.stream;

  bool get isConnected => _subscription != null;

  /// Opens (or re-opens) the stream with [token]. Safe to call repeatedly:
  /// an existing healthy connection with the same token is kept.
  void connect(String token) {
    if (_disposed || token.isEmpty) return;
    if (isConnected && _token == token) return;
    _token = token;
    disconnectSocket();
    _open();
  }

  /// Closes the socket and cancels any pending reconnect (logout).
  void disconnect() {
    _token = null;
    disconnectSocket();
  }

  /// App-resume hook: reconnect immediately when logged in but the socket
  /// dropped.  Resets backoff to minimum for instant recovery.
  void reconnectIfNeeded() {
    if (_disposed) return;
    final token = _token;
    if (token == null || token.isEmpty) return;
    if (!isConnected && _reconnectTimer == null) {
      _backoff = _minBackoff; // immediate reconnect
      _open();
    }
  }

  void dispose() {
    _disposed = true;
    disconnect();
    _events.close();
    _connStateController.close();
  }

  // ---- internals ------------------------------------------------------------

  void _open() {
    if (_disposed || _token == null || _token!.isEmpty) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    final client = http.Client();
    _client = client;
    final uri = Uri.parse(
      '$_base/realtime/softbase/stream?token=${Uri.encodeQueryComponent(_token!)}',
    );

    Future(() async {
      final request = http.Request('GET', uri)
        ..headers['Accept'] = 'text/event-stream'
        ..headers['Cache-Control'] = 'no-cache';
      final response = await client.send(request);
      if (response.statusCode >= 400) {
        throw StateError('softbase stream status ${response.statusCode}');
      }
      return response.stream;
    }).then((body) {
      _connectedAt = DateTime.now();
      _backoff = _minBackoff; // reset backoff after a successful open
      _connState = 'connected';
      _connStateController.add(_connState);
      debugPrint('[SoftBase] 🟢 connected');
      var buffer = '';
      _subscription = body.listen(
        (chunk) {
          buffer += utf8.decode(chunk, allowMalformed: true);
          while (true) {
            final idx = buffer.indexOf('\n');
            if (idx < 0) break;
            final line = buffer.substring(0, idx).replaceFirst('\r', '');
            buffer = buffer.substring(idx + 1);
            _handleLine(line);
          }
          // Flush a trailing complete frame without newline (rare).
          if (buffer.isNotEmpty && buffer.contains('data:')) {
            _handleLine(buffer.replaceFirst('\r', ''));
            buffer = '';
          }
        },
        onError: (_) => _scheduleReconnect(),
        onDone: () => _scheduleReconnect(),
        cancelOnError: false,
      );
    }).catchError((Object _) {
      _closeSocket();
      _scheduleReconnect();
    });
  }

  /// Incremental SSE parser state for the current frame block.
  String _eventName = '';
  String _lastEventId = '';
  final List<String> _dataLines = <String>[];

  void _handleLine(String line) {
    if (line.startsWith(':')) return; // heartbeat comment (`: hb`)
    if (line.startsWith('retry:')) return; // server-advised retry interval
    if (line.trim().isEmpty) {
      _dispatchFrame();
      return;
    }
    if (line.startsWith('event:')) {
      _eventName = line.substring(6).trim();
      return;
    }
    if (line.startsWith('data:')) {
      _dataLines.add(line.length > 5 ? line.substring(5).trimLeft() : '');
      return;
    }
    if (line.startsWith('id:')) {
      _lastEventId = line.substring(3).trim();
      return;
    }
  }

  void _dispatchFrame() {
    if (_dataLines.isEmpty) return;
    final raw = _dataLines.join('\n');
    final sseEventName = _eventName;
    _eventName = '';
    _dataLines.clear();
    if (raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      // Fall back to the SSE `event:` field when the JSON payload has no
      // explicit `type` of its own.
      if (decoded['type'] == null &&
          sseEventName.isNotEmpty &&
          sseEventName != 'message') {
        decoded['type'] = sseEventName;
      }
      final event =
          SoftBaseEvent.fromJson(Map<String, dynamic>.from(decoded));
      if (event.type.isEmpty) return;

      // Deduplicate by event id (SSE `id:` field) — bounded LRU set.
      final eid = _lastEventId.isNotEmpty ? _lastEventId : event.id;
      _lastEventId = '';
      if (eid.isNotEmpty) {
        if (_seenEventIds.contains(eid)) return; // duplicate
        _seenEventIds.add(eid);
        if (_seenEventIds.length > _maxSeenIds) {
          _seenEventIds.remove(_seenEventIds.first);
        }
      }

      _events.add(event);
    } catch (_) {
      // Malformed frames are dropped silently.
    }
  }

  void _closeSocket() {
    _subscription?.cancel();
    _subscription = null;
    _client?.close();
    _client = null;
    _connectedAt = null;
    _connState = 'disconnected';
    _connStateController.add(_connState);
  }

  void disconnectSocket() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _closeSocket();
    _eventName = '';
    _dataLines.clear();
  }

  void _scheduleReconnect() {
    _closeSocket();
    if (_disposed || _token == null || _token!.isEmpty) return;
    // A connection that stayed healthy counts as success → reset the ladder.
    final healthy = _connectedAt != null &&
        DateTime.now().difference(_connectedAt!) > _healthyAfter;
    _backoff = healthy ? _minBackoff : _backoff * 2;
    if (_backoff > _maxBackoff) _backoff = _maxBackoff;
    // Add ±20% jitter to avoid thundering-herd reconnects.
    final jitterMs = (_backoff.inMilliseconds * 0.2).round();
    final jitter =
        Duration(milliseconds: math.Random().nextInt(jitterMs * 2 + 1) - jitterMs);
    final delay = _backoff + jitter;
    _connState = 'reconnecting';
    _connStateController.add(_connState);
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, _open);
  }
}
