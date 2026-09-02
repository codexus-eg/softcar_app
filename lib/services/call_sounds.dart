import 'dart:async';

import 'package:just_audio/just_audio.dart';

/// Tiny wrapper over just_audio for the bundled call sound assets
/// (`assets/sounds/*.m4a`). Each kind owns one player instance registered in
/// [players] **before** playback starts, so [stop] can always interrupt it —
/// including looped ringtone/hold audio whose `play()` future never resolves
/// until stopped. Callers must stop through the public helpers when a call
/// screen goes away.
class CallSounds {
  CallSounds._();

  static final CallSounds instance = CallSounds._();

  final Map<String, AudioPlayer> _players = {};

  AudioPlayer? _player(String key) => _players[key];

  /// Starts a sound of [key], optionally looping. Re-plays an already playing
  /// loop as a no-op (never stacks an overlapping copy); a one-shot that is
  /// started while the same kind is still playing is restarted.
  Future<void> _start(String key, String asset, {required bool loop}) async {
    final existing = _player(key);
    if (existing != null) {
      if (loop) return;
      await _stopPlayer(key, existing);
    }
    try {
      final player = AudioPlayer();
      _players[key] = player; // register BEFORE play so stop() can find us
      await player.setAsset(asset);
      if (loop) player.setLoopMode(LoopMode.one);
      unawaited(
        player.play().then<void>(
          (_) => releaseIfCurrent(key, player),
        ).catchError((_) {
          releaseIfCurrent(key, player);
        }),
      );
    } catch (_) {
      releaseIfCurrent(key, _player(key));
    }
  }

  /// Incoming-call ringtone, looped until [stopRingtone].
  Future<void> playRingtone() =>
      _start('ringtone', 'assets/sounds/ringtone.m4a', loop: true);

  Future<void> stopRingtone() => stopKey('ringtone');

  /// IVR hold music while waiting for an agent, looped.
  Future<void> playHold() =>
      _start('hold', 'assets/sounds/hold.m4a', loop: true);

  Future<void> stopHold() => stopKey('hold');

  /// Call-center greeting message played once.
  Future<void> playGreeting() =>
      _start('greeting', 'assets/sounds/greeting.m4a', loop: false);

  Future<void> stopGreeting() => stopKey('greeting');

  /// Short IVR confirmation beep.
  Future<void> playBeep() =>
      _start('beep', 'assets/sounds/ivr-beep.m4a', loop: false);

  Future<void> stopBeep() => stopKey('beep');

  /// Stops every looping/one-shot sound (call teardown, screen exit).
  Future<void> stopAll() async {
    for (final key in _players.keys.toList()) {
      await stopKey(key);
    }
  }

  Future<void> stopKey(String key) async {
    final player = _players[key];
    if (player == null) return;
    await _stopPlayer(key, player);
  }

  Future<void> _stopPlayer(String key, AudioPlayer player) async {
    if (_players[key] != player) return;
    _players.remove(key);
    try {
      await player.stop();
    } catch (_) {}
    try {
      await player.dispose();
    } catch (_) {}
  }

  void releaseIfCurrent(String key, AudioPlayer? player) {
    if (player != null && _players[key] == player) {
      _players.remove(key);
    }
  }
}