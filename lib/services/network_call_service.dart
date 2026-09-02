import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

typedef CallRefresh = Future<Map<String, dynamic>?> Function(String id);
typedef SignalSend =
    Future<void> Function(
      String callId,
      String type,
      Map<String, dynamic> payload,
    );
typedef SignalReceive =
    Future<List<Map<String, dynamic>>> Function(String callId, DateTime? after);
typedef CallEnd = Future<void> Function(String id);

/// Audio-only WebRTC controller. Signalling is persisted by the production
/// API, so calls work across mobile networks without exposing phone numbers.
class NetworkCallService extends ChangeNotifier {
  NetworkCallService({
    required this.refreshCall,
    required this.sendSignal,
    required this.receiveSignals,
    required this.endRemoteCall,
  });

  final CallRefresh refreshCall;
  final SignalSend sendSignal;
  final SignalReceive receiveSignals;
  final CallEnd endRemoteCall;

  RTCPeerConnection? _peer;
  MediaStream? _localStream;
  Timer? _poller;
  final Set<String> _handledSignals = {};
  DateTime? _signalCursor;
  Map<String, dynamic>? _session;
  bool _caller = false;
  bool _offerSent = false;
  bool _muted = false;
  bool _speaker = false;
  bool _busy = false;
  String? _error;
  String _connectionState = 'idle';

  Map<String, dynamic>? get session => _session;
  String get callId => _session?['id']?.toString() ?? '';
  String get status => _session?['status']?.toString() ?? 'IDLE';
  int? get queuePosition => _session?['queuePosition'] as int?;
  String? get agentName =>
      _session?['assignedTo'] is Map
          ? (_session!['assignedTo'] as Map)['name']?.toString()
          : null;
  String get connectionState => _connectionState;
  bool get muted => _muted;
  bool get speaker => _speaker;
  bool get busy => _busy;
  String? get error => _error;
  bool get isFinished =>
      ['ENDED', 'CANCELLED', 'MISSED', 'FAILED'].contains(status);

  Future<void> startCaller(Map<String, dynamic> session) async {
    await disposeCall();
    _caller = true;
    _session = session;
    _connectionState = 'waiting';
    notifyListeners();
    _startPolling();
    if (['ASSIGNED', 'CONNECTING', 'ACTIVE'].contains(status)) {
      await _ensureCallerOffer();
    }
  }

  Future<void> answerAsAgent(Map<String, dynamic> session) async {
    await disposeCall();
    _caller = false;
    _session = session;
    _connectionState = 'connecting';
    notifyListeners();
    await _ensurePeer();
    _startPolling();
    await _poll();
  }

  Future<void> _ensureCallerOffer() async {
    if (_offerSent || !_caller || callId.isEmpty) return;
    await _ensurePeer();
    final offer = await _peer!.createOffer({'offerToReceiveAudio': true});
    await _peer!.setLocalDescription(offer);
    await sendSignal(callId, 'OFFER', {'sdp': offer.sdp, 'type': offer.type});
    _offerSent = true;
    _connectionState = 'connecting';
    notifyListeners();
  }

  Future<void> _ensurePeer() async {
    if (_peer != null) return;
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      final servers =
          _session?['iceServers'] is List
              ? List<Map<String, dynamic>>.from(
                (_session!['iceServers'] as List).whereType<Map>().map(
                  (item) => Map<String, dynamic>.from(item),
                ),
              )
              : <Map<String, dynamic>>[
                {
                  'urls': [
                    'stun:stun.l.google.com:19302',
                    'stun:stun1.l.google.com:19302',
                  ],
                },
              ];
      _peer = await createPeerConnection({'iceServers': servers});
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': {
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
        if (candidate.candidate == null || callId.isEmpty) return;
        unawaited(
          sendSignal(callId, 'ICE', {
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
          }),
        );
      };
      _peer!.onConnectionState = (state) {
        _connectionState = state.name;
        notifyListeners();
      };
    } catch (e) {
      _error = 'Could not start the microphone or network call.';
      _connectionState = 'failed';
      rethrow;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  void _startPolling() {
    _poller?.cancel();
    _poller = Timer.periodic(const Duration(milliseconds: 1400), (_) {
      unawaited(_poll());
    });
  }

  Future<void> _poll() async {
    if (callId.isEmpty || isFinished) return;
    try {
      final fresh = await refreshCall(callId);
      if (fresh != null) _session = fresh;
      if (_caller && ['ASSIGNED', 'CONNECTING', 'ACTIVE'].contains(status)) {
        await _ensureCallerOffer();
      }
      final signals = await receiveSignals(callId, _signalCursor);
      for (final signal in signals) {
        final id = signal['id']?.toString() ?? '';
        if (id.isEmpty || !_handledSignals.add(id)) continue;
        final createdAt = DateTime.tryParse(
          signal['createdAt']?.toString() ?? '',
        );
        if (createdAt != null &&
            (_signalCursor == null || createdAt.isAfter(_signalCursor!))) {
          _signalCursor = createdAt;
        }
        await _handleSignal(signal);
      }
      if (isFinished) await _disposeMedia();
      notifyListeners();
    } catch (_) {
      // A temporary mobile-network interruption is retried by the next poll.
    }
  }

  Future<void> _handleSignal(Map<String, dynamic> signal) async {
    final type = signal['type']?.toString().toUpperCase() ?? '';
    final payload =
        signal['payload'] is Map
            ? Map<String, dynamic>.from(signal['payload'] as Map)
            : <String, dynamic>{};
    if (type == 'HANGUP') {
      _connectionState = 'ended';
      await _disposeMedia();
      return;
    }
    await _ensurePeer();
    if (type == 'OFFER' && !_caller) {
      await _peer!.setRemoteDescription(
        RTCSessionDescription(payload['sdp']?.toString(), 'offer'),
      );
      final answer = await _peer!.createAnswer({'offerToReceiveAudio': true});
      await _peer!.setLocalDescription(answer);
      await sendSignal(callId, 'ANSWER', {
        'sdp': answer.sdp,
        'type': answer.type,
      });
    } else if (type == 'ANSWER' && _caller) {
      await _peer!.setRemoteDescription(
        RTCSessionDescription(payload['sdp']?.toString(), 'answer'),
      );
    } else if (type == 'ICE') {
      await _peer!.addCandidate(
        RTCIceCandidate(
          payload['candidate']?.toString(),
          payload['sdpMid']?.toString(),
          payload['sdpMLineIndex'] as int?,
        ),
      );
    }
  }

  Future<void> toggleMute() async {
    _muted = !_muted;
    for (final track
        in _localStream?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      track.enabled = !_muted;
    }
    notifyListeners();
  }

  Future<void> toggleSpeaker() async {
    _speaker = !_speaker;
    await Helper.setSpeakerphoneOn(_speaker);
    notifyListeners();
  }

  Future<void> hangUp() async {
    if (callId.isNotEmpty && !isFinished) {
      await sendSignal(callId, 'HANGUP', const {});
      await endRemoteCall(callId);
    }
    _connectionState = 'ended';
    await _disposeMedia();
    notifyListeners();
  }

  Future<void> _disposeMedia() async {
    _poller?.cancel();
    _poller = null;
    for (final track in _localStream?.getTracks() ?? <MediaStreamTrack>[]) {
      track.stop();
    }
    await _localStream?.dispose();
    _localStream = null;
    await _peer?.close();
    _peer = null;
  }

  Future<void> disposeCall() async {
    await _disposeMedia();
    _handledSignals.clear();
    _signalCursor = null;
    _session = null;
    _offerSent = false;
    _error = null;
    _connectionState = 'idle';
  }

  @override
  void dispose() {
    unawaited(_disposeMedia());
    super.dispose();
  }
}
