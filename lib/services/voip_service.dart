import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'call_sounds.dart';

/// Wire format adapters so [VoipService] stays identical across apps; each
/// app wires these to its own API client (`passengerApi` / `SoftCarApi`) and
/// its bearer token provider.
typedef VoipPostSessions =
    Future<Map<String, dynamic>> Function(Map<String, dynamic> body);
typedef VoipGetSession = Future<Map<String, dynamic>> Function(String id);
typedef VoipSendSignal =
    Future<void> Function(
      String callSessionId,
      String type,
      Map<String, dynamic> payload,
    );
typedef VoipGetSignals =
    Future<List<Map<String, dynamic>>> Function(
      String callSessionId,
      DateTime? after,
    );

/// High-level lifecycle of one Soft-Call inside the app.
enum VoipPhase {
  idle,
  outgoingQueued,
  outgoingWaiting,
  connecting,
  active,
  reconnecting,
  ended,
}

/// Full Soft-Call engine: session REST actions, polling loops and the
/// audio-only WebRTC peer. The side that CREATED the session is the
/// initiator and posts the SDP OFFER once the call reaches CONNECTING with
/// `acceptedAt`; the receiving side answers. ICE candidates trickle through
/// the same signals endpoint. Incoming rings arrive via SoftBase
/// (`VOIP_RING`) and surface through [incomingRing].
class VoipService extends ChangeNotifier {
  VoipService._();

  static final VoipService instance = VoipService._();

  bool _wired = false;
  late VoipPostSessions _postSessions;
  late VoipGetSession _getSession;
  late VoipSendSignal _sendSignalFn;
  late VoipGetSignals _getSignalsFn;

  /// Must be called once at app boot, before any call UI can open.
  void wire({
    required VoipPostSessions postSessions,
    required VoipGetSession getSession,
    required VoipSendSignal sendSignal,
    required VoipGetSignals getSignals,
  }) {
    _postSessions = postSessions;
    _getSession = getSession;
    _sendSignalFn = sendSignal;
    _getSignalsFn = getSignals;
    _wired = true;
  }

  // ---- state ----------------------------------------------------------------
  Map<String, dynamic>? _session;
  bool _initiator = false;
  bool _offerSent = false;
  bool _answerSent = false;
  VoipPhase _phase = VoipPhase.idle;
  String? _remoteName;
  String? _remoteRole;
  String? _remoteImage;
  String? _maskedNumber;
  String? _lane;
  String? _lastErrorKey;
  bool _muted = false;
  bool _speakerOn = false;
  int _elapsedSeconds = 0;
  String _connectionState = 'idle';

  /// Pending incoming ring (raw VOIP_RING `data` map) shown full-screen.
  Map<String, dynamic>? _incomingRing;

  Timer? _ticker;
  DateTime? _signalCursor;
  final Set<String> _handledSignals = {};
  Timer? _ringTimeout;

  RTCPeerConnection? _peer;
  MediaStream? _localStream;
  DateTime? _lastHealthyTick;
  static const _deadCallThreshold = Duration(seconds: 20);

  // ---- getters --------------------------------------------------------------
  VoipPhase get phase => _phase;
  Map<String, dynamic>? get incomingRing => _incomingRing;
  Map<String, dynamic>? get session => _session;
  String get sessionId => _session?['id']?.toString() ?? '';
  String get status =>
      (_session?['status']?.toString() ?? 'IDLE').toUpperCase();
  int? get queuePosition {
    final raw = _session?['queuePosition'] ?? _session?['queue_position'];
    return raw is int ? raw : int.tryParse('${raw ?? ''}');
  }

  String? get remoteName => _remoteName;
  String? get remoteRole => _remoteRole;
  String? get remoteImage => _remoteImage;
  String? get maskedNumber => _maskedNumber;
  String? get lane => _lane;
  bool get isMuted => _muted;
  bool get isSpeakerOn => _speakerOn;
  int get elapsedSeconds => _elapsedSeconds;
  String get connectionState => _connectionState;
  String? get lastErrorKey => _lastErrorKey;
  bool get isActiveCall =>
      _phase == VoipPhase.connecting ||
      _phase == VoipPhase.active ||
      _phase == VoipPhase.reconnecting;

  static const _terminalStatuses = ['ENDED', 'CANCELLED', 'MISSED', 'FAILED'];

  // ---- outgoing calls -------------------------------------------------------

  /// Creates a free in-app Soft-Call straight to another user (driver ↔
  /// passenger). Returns the created session or throws.
  Future<Map<String, dynamic>> createDirectCall(
    String targetUserId, {
    String? tripId,
    String? reason = '',
  }) async {
    _assertWired();
    final json = await _postSessions(<String, dynamic>{
      'action': 'create',
      'targetUserId': targetUserId,
      if (tripId != null && tripId.isNotEmpty) 'tripId': tripId,
      'reason': (reason == null || reason.trim().isEmpty)
          ? 'Direct Soft-Call'
          : reason.trim(),
      'priority': 1,
    });
    final session = _extractSession(json);
    await startOutgoing(session);
    return session;
  }

  /// Starts the IVR flow towards the call center ([supportLane] is one of
  /// CALL_CENTER / RESERVATIONS / COMPLAINTS).
  Future<Map<String, dynamic>> createSupportLaneCall({
    required String supportLane,
    String reason = '',
    int priority = 0,
  }) async {
    _assertWired();
    final json = await _postSessions(<String, dynamic>{
      'action': 'create',
      'supportLane': supportLane,
      'reason': (reason.trim().isEmpty) ? 'Call center request' : reason.trim(),
      'priority': priority,
    });
    final session = _extractSession(json);
    await startOutgoing(session);
    return session;
  }

  /// Adopts a freshly-created session as the INITIATOR (this side will send
  /// the offer once an agent/peer accepts).
  Future<void> startOutgoing(Map<String, dynamic> session) async {
    await resetCall();
    _session = session;
    _initiator = true;
    _offerSent = false;
    _answerSent = false;
    _applyRemoteFromSession(session);
    _phase = switch (status) {
      'QUEUED' => VoipPhase.outgoingQueued,
      'ASSIGNED' => VoipPhase.outgoingWaiting,
      _ => VoipPhase.connecting,
    };
    _connectionState = 'waiting';
    notifyListeners();
    _ensureTicker();
    // Initiator may already be accepted (fast agent pickup).
    await _maybeSendOffer();
  }

  // ---- incoming calls -------------------------------------------------------

  /// A VOIP_RING frame arrived over SoftBase. Stores the ring so the host
  /// widget can push the full-screen incoming-call UI. The ring self-cancels
  /// after 45s (server cancel) if nobody answers.
  void handleRing(Map<String, dynamic> data) {
    final callId = data['callSessionId']?.toString() ?? '';
    if (callId.isEmpty) return;
    if (isActiveCall) return; // never clobber a live call
    _incomingRing = Map<String, dynamic>.from(data);
    _lastErrorKey = null;
    startRingTimeout();
    notifyListeners();
  }

  void clearIncomingRing() {
    _incomingRing = null;
    _stopRingTimeout();
    notifyListeners();
  }

  /// Callee path: adopt the rung session and prepare to ANSWER. Returns
  /// false when the call already finished (late accept → caller sees the
  /// "call ended" snackbar).
  Future<bool> acceptIncoming() async {
    _assertWired();
    final ring = _incomingRing;
    final callId = ring?['callSessionId']?.toString() ?? '';
    if (callId.isEmpty) return false;
    _incomingRing = null;
    _stopRingTimeout();

    Map<String, dynamic> session;
    try {
      session = _extractSession(await _getSession(callId));
    } catch (_) {
      session = <String, dynamic>{'id': callId};
    }
    if (_terminalStatuses.contains(
      (session['status']?.toString() ?? '').toUpperCase(),
    )) {
      _lastErrorKey = 'calls.callEnded';
      _phase = VoipPhase.idle;
      notifyListeners();
      return false;
    }

    await resetCall();
    _session = session;
    _initiator = false;
    _offerSent = false;
    _answerSent = false;
    _applyRemoteFromSession(session);
    if (_remoteName == null && ring != null) {
      _remoteName = ring['fromName']?.toString();
      _remoteRole = ring['fromRole']?.toString();
      _maskedNumber = ring['maskedNumber']?.toString();
      _lane = ring['supportLane']?.toString();
    }
    _phase = VoipPhase.connecting;
    _connectionState = 'connecting';
    notifyListeners();

    // Mark acceptance server-side (best effort — some flows auto-accept).
    try {
      await _postSessions(<String, dynamic>{'action': 'accept', 'id': callId});
    } catch (_) {}
    await _ensurePeer();
    _ensureTicker();
    notifyListeners();
    return true;
  }

  /// Declines a ringing incoming call (cancel action) or dismisses it.
  Future<void> declineIncoming() async {
    final ring = _incomingRing;
    _incomingRing = null;
    _stopRingTimeout();
    final callId = ring?['callSessionId']?.toString() ?? '';
    if (callId.isNotEmpty && _wired) {
      try {
        await _postSessions(<String, dynamic>{'action': 'cancel', 'id': callId});
      } catch (_) {}
    }
    notifyListeners();
  }

  void startRingTimeout({Duration timeout = const Duration(seconds: 45)}) {
    _stopRingTimeout();
    _ringTimeout = Timer(timeout, () {
      if (_incomingRing != null) unawaited(declineIncoming());
    });
  }

  void _stopRingTimeout() {
    _ringTimeout?.cancel();
    _ringTimeout = null;
  }

  // ---- in-call controls -----------------------------------------------------

  /// Called by the host widget on network-change or app-resume mid-call.
  /// Restarts signal polling and re-GETs the session for fresh ICE servers.
  Future<void> reconnectAfterNetworkChange() async {
    if (!isActiveCall) return;
    try {
      final fresh = _extractSession(await _getSession(sessionId));
      if (fresh.isNotEmpty) {
        _session = Map<String, dynamic>.from(_session ?? const {})
          ..addAll(fresh);
        _lastHealthyTick = DateTime.now();
      }
    } catch (_) {}
    _ensureTicker();
    notifyListeners();
  }

  Future<void> toggleMute() async {
    _muted = !_muted;
    for (final track in _localStream?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      track.enabled = !_muted;
    }
    notifyListeners();
  }

  Future<void> toggleSpeaker() async {
    _speakerOn = !_speakerOn;
    try {
      await Helper.setSpeakerphoneOn(_speakerOn);
    } catch (_) {}
    notifyListeners();
  }

  /// Hangs up: HANGUP signal + end action + local teardown.
  Future<void> hangUp() async {
    final id = sessionId;
    if (id.isNotEmpty &&
        !_terminalStatuses.contains(status) &&
        _phase != VoipPhase.idle) {
      try {
        await _sendSignalFn(id, 'HANGUP', <String, dynamic>{});
      } catch (_) {}
      try {
        await _postSessions(<String, dynamic>{'action': 'end', 'id': id});
      } catch (_) {}
    }
    await _teardownMedia();
    _phase = VoipPhase.ended;
    notifyListeners();
  }

  /// Clears everything back to idle (after the ended screen popped).
  Future<void> resetCall() async {
    await _teardownMedia();
    _session = null;
    _initiator = false;
    _offerSent = false;
    _answerSent = false;
    _phase = VoipPhase.idle;
    _remoteName = null;
    _remoteRole = null;
    _remoteImage = null;
    _maskedNumber = null;
    _elapsedSeconds = 0;
    _connectionState = 'idle';
    _muted = false;
    _handledSignals.clear();
    _signalCursor = null;
  }

  // ---- polling loops --------------------------------------------------------

  void _ensureTicker() {
    _ticker?.cancel();
    // Cadence follows the backend contract: ~2s queue polling while
    // QUEUED, 800ms signal polling during CONNECTING, 1500ms when ACTIVE.
    _ticker = Timer(_intervalFor(), () {
      unawaited(_tick());
    });
  }

  Duration _intervalFor() {
    switch (_phase) {
      case VoipPhase.outgoingQueued:
      case VoipPhase.outgoingWaiting:
        return const Duration(seconds: 2); // queue position poll
      case VoipPhase.connecting:
        return const Duration(milliseconds: 800);
      case VoipPhase.active:
      case VoipPhase.reconnecting:
        return const Duration(milliseconds: 1500);
      default:
        return const Duration(seconds: 2);
    }
  }

  Future<void> _tick() async {
    if (_phase == VoipPhase.idle || _phase == VoipPhase.ended) return;
    var healthy = true;
    try {
      final id = sessionId;
      if (id.isEmpty) return;

      // Fresh session incl. queuePosition.
      final fresh = _extractSession(await _getSession(id));
      if (fresh.isNotEmpty) {
        _session = Map<String, dynamic>.from(_session ?? const {})
          ..addAll(fresh);
        _applyRemoteFromSession(_session!);
        _lastHealthyTick = DateTime.now();
      }
      final st = status;
      if (_terminalStatuses.contains(st)) {
        await _teardownMedia();
        _phase = VoipPhase.ended;
        notifyListeners();
        return;
      }
      if (_initiator) {
        await _maybeSendOffer();
      }

      // Signals since the last cursor.
      final signals = await _getSignalsFn(id, _signalCursor);
      for (final signal in signals) {
        final type = signal['type']?.toString().toUpperCase() ?? '';
        final createdAt = signal['createdAt']?.toString() ?? '';
        final key = '$createdAt|$type';
        if (!_handledSignals.add(key)) continue;
        final parsed = DateTime.tryParse(createdAt);
        if (parsed != null &&
            (_signalCursor == null || parsed.isAfter(_signalCursor!))) {
          _signalCursor = parsed;
        }
        await _handleSignal(type, signal['payload']);
      }
    } catch (_) {
      healthy = false; // transient network hiccup — next tick retries
    }

    if (_terminalStatuses.contains(status)) {
      await _teardownMedia();
      _phase = VoipPhase.ended;
      notifyListeners();
      return;
    }

    // Phase transitions driven by backend status + peer state.
    final st = status;
    if (_phase == VoipPhase.active &&
        (_connectionState.contains('Disconnected') ||
            _connectionState.contains('Failed'))) {
      _phase = VoipPhase.reconnecting;
    } else if (_initiator && st == 'QUEUED') {
      _phase = VoipPhase.outgoingQueued;
    } else if (_initiator && st == 'ASSIGNED' && _offerSent != true) {
      _phase = VoipPhase.outgoingWaiting;
    } else if (_phase == VoipPhase.outgoingQueued ||
        _phase == VoipPhase.outgoingWaiting ||
        _phase == VoipPhase.reconnecting) {
      _phase = (_connectionState.contains('Connected'))
          ? VoipPhase.active
          : (_connectionState.contains('Disconnected') ||
                  _connectionState.contains('Failed'))
              ? VoipPhase.reconnecting
              : VoipPhase.connecting;
    }
    if (!healthy &&
        _phase == VoipPhase.active) {
      _phase = VoipPhase.reconnecting;
    }

    // Dead-call detection: >20s without a successful tick → reconnecting.
    if (_lastHealthyTick != null &&
        DateTime.now().difference(_lastHealthyTick!) > _deadCallThreshold &&
        (_phase == VoipPhase.active || _phase == VoipPhase.connecting)) {
      _phase = VoipPhase.reconnecting;
    }

    notifyListeners();
    _ensureTicker();
  }

  // ---- signalling -----------------------------------------------------------

  Future<void> _maybeSendOffer() async {
    if (!_initiator || _offerSent) return;
    final st = status;
    final acceptedAt = _session?['acceptedAt'] ?? _session?['accepted_at'];
    if ((st != 'CONNECTING' && st != 'ACTIVE') || acceptedAt == null) return;
    await _ensurePeer();
    try {
      final offer = await _peer!.createOffer({'offerToReceiveAudio': true});
      await _peer!.setLocalDescription(offer);
      await _sendSignalFn(sessionId, 'OFFER', <String, dynamic>{
        'sdp': offer.sdp,
        'type': offer.type,
      });
      _offerSent = true;
      _phase = VoipPhase.connecting;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _handleSignal(String type, Object? payloadRaw) async {
    final payload = payloadRaw is Map
        ? Map<String, dynamic>.from(payloadRaw)
        : <String, dynamic>{};
    switch (type) {
      case 'HANGUP':
        try {
          await _postSessions(
            <String, dynamic>{'action': 'end', 'id': sessionId},
          );
        } catch (_) {}
        await _teardownMedia();
        _phase = VoipPhase.ended;
        notifyListeners();
        return;
      case 'OFFER':
        if (_initiator) return; // only the callee answers offers
        await _ensurePeer();
        try {
          await _peer!.setRemoteDescription(
            RTCSessionDescription(payload['sdp']?.toString(), 'offer'),
          );
          final answer =
              await _peer!.createAnswer({'offerToReceiveAudio': true});
          await _peer!.setLocalDescription(answer);
          if (!_answerSent) {
            await _sendSignalFn(sessionId, 'ANSWER', <String, dynamic>{
              'sdp': answer.sdp,
              'type': answer.type,
            });
            _answerSent = true;
          }
          _phase = VoipPhase.connecting;
          notifyListeners();
        } catch (_) {}
        return;
      case 'ANSWER':
        if (!_initiator) return;
        try {
          await _ensurePeer();
          final current = await _peer!.getRemoteDescription();
          if (current == null) {
            await _peer!.setRemoteDescription(
              RTCSessionDescription(payload['sdp']?.toString(), 'answer'),
            );
            _phase = VoipPhase.connecting;
            notifyListeners();
          }
        } catch (_) {}
        return;
      case 'ICE':
        try {
          await _ensurePeer();
          await _peer!.addCandidate(
            RTCIceCandidate(
              payload['candidate']?.toString(),
              payload['sdpMid']?.toString(),
              payload['sdpMLineIndex'] is int
                  ? payload['sdpMLineIndex'] as int
                  : int.tryParse('${payload['sdpMLineIndex']}'),
            ),
          );
        } catch (_) {}
        return;
      default:
        return;
    }
  }

  // ---- WebRTC peer ----------------------------------------------------------

  Future<void> _ensurePeer() async {
    if (_peer != null) return;
    final iceRaw = _session?['iceServers'];
    final servers = <Map<String, dynamic>>[];
    if (iceRaw is List) {
      for (final item in iceRaw) {
        if (item is Map) servers.add(Map<String, dynamic>.from(item));
      }
    }
    if (servers.isEmpty) {
      servers.add(<String, dynamic>{
        'urls': [
          'stun:stun.l.google.com:19302',
          'stun:stun1.l.google.com:19302',
        ],
      });
    }
    _peer = await createPeerConnection({'iceServers': servers});
    _localStream = await navigator.mediaDevices.getUserMedia(<String, dynamic>{
      'audio': <String, dynamic>{
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
      },
      'video': false,
    });
    for (final track in _localStream!.getAudioTracks()) {
      await _peer!.addTrack(track, _localStream!);
    }
    _peer!.onIceCandidate = (candidate) {
      if (candidate.candidate == null || sessionId.isEmpty) return;
      unawaited(
        _sendSignalFn(
          sessionId,
          'ICE',
          <String, dynamic>{
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
          },
        ),
      );
    };
    _peer!.onConnectionState = (state) {
      _connectionState = state.name;
      switch (state.name) {
        case 'RTCPeerConnectionStateConnected':
          _phase = VoipPhase.active;
          // Stop hold music immediately — the call is live.
          CallSounds.instance.stopAll();
          _startDurationTimer();
          break;
        case 'RTCPeerConnectionStateDisconnected':
        case 'RTCPeerConnectionStateFailed':
          if (_phase == VoipPhase.active) _phase = VoipPhase.reconnecting;
          break;
      }
      notifyListeners();
    };
  }

  void _startDurationTimer() {
    if (_elapsedSeconds > 0) return;
    Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_phase != VoipPhase.active) {
        timer.cancel();
        return;
      }
      _elapsedSeconds++;
      notifyListeners();
    });
  }

  Future<void> _teardownMedia() async {
    _ticker?.cancel();
    _ticker = null;
    for (final track in _localStream?.getTracks() ?? <MediaStreamTrack>[]) {
      try {
        track.stop();
      } catch (_) {}
    }
    try {
      await _localStream?.dispose();
    } catch (_) {}
    _localStream = null;
    try {
      await _peer?.close();
    } catch (_) {}
    _peer = null;
    await CallSounds.instance.stopAll();
  }

  // ---- helpers --------------------------------------------------------------

  void _applyRemoteFromSession(Map<String, dynamic> session) {
    final assigned = session['assignedTo'] is Map
        ? Map<String, dynamic>.from(session['assignedTo'] as Map)
        : <String, dynamic>{};
    if (assigned.isNotEmpty) {
      _remoteName = assigned['name']?.toString();
      _remoteRole = assigned['role']?.toString();
      _remoteImage = assigned['image']?.toString();
    }
    final target = session['targetUser'] is Map
        ? Map<String, dynamic>.from(session['targetUser'] as Map)
        : <String, dynamic>{};
    if (target.isNotEmpty) {
      _remoteName ??= target['name']?.toString();
      _remoteRole ??= target['role']?.toString();
      _remoteImage ??= target['image']?.toString();
    }
    _maskedNumber = session['maskedNumber']?.toString() ?? _maskedNumber;
    _lane = session['supportLane']?.toString() ?? session['lane']?.toString() ?? _lane;
  }

  Map<String, dynamic> _extractSession(Map<String, dynamic> json) {
    final raw = json['session'];
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (json['id'] != null) {
      final copy = Map<String, dynamic>.from(json);
      // Hoist envelope fields the backend keeps beside `session`.
      for (final key in ['queuePosition', 'iceServers']) {
        if (copy[key] == null && json['session'] == null) break;
      }
      return copy;
    }
    return const <String, dynamic>{};
  }

  void _assertWired() {
    if (!_wired) {
      throw StateError('VoipService.wire() must be called before use');
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _ringTimeout?.cancel();
    // Always send HANGUP on dispose so the other side knows we left.
    final id = sessionId;
    if (id.isNotEmpty && isActiveCall && _wired) {
      try {
        _sendSignalFn(id, 'HANGUP', <String, dynamic>{});
      } catch (_) {}
      try {
        _postSessions(<String, dynamic>{'action': 'end', 'id': id});
      } catch (_) {}
    }
    unawaited(_teardownMedia());
    super.dispose();
  }
}
