import 'dart:async';

import 'package:flutter/material.dart';

/// Global navigation for code outside the widget tree (notification taps).
/// Owns the root navigator key and buffers one pending route until the splash
/// bootstrap has finished, so a cold-start notification tap lands on the
/// target screen instead of being wiped by the splash redirect.
class AppNav {
  AppNav._();

  static final GlobalKey<NavigatorState> key = GlobalKey<NavigatorState>();

  static const _retryInterval = Duration(milliseconds: 400);
  static const _maxWait = Duration(seconds: 15);

  static bool splashDone = false;
  static DateTime? _queuedAt;
  static Map<String, Object?>? _pending;
  static Timer? _retry;

  /// Navigates immediately when the shell is ready; otherwise buffers the
  /// route until [splashFinished] (or a safety timeout) flushes it.
  static void go(String route, {Object? arguments}) {
    if (splashDone) {
      key.currentState?.pushNamed(route, arguments: arguments);
      return;
    }
    _pending = <String, Object?>{'route': route, 'arguments': arguments};
    _queuedAt ??= DateTime.now();
    _startRetry();
  }

  /// Called once the splash screen has completed its bootstrap redirect.
  static void splashFinished() {
    splashDone = true;
    _startRetry();
  }

  static void _startRetry() {
    _retry ??= Timer.periodic(_retryInterval, (_) {
      final pending = _pending;
      if (pending == null || key.currentContext == null) {
        if (pending == null) {
          _retry?.cancel();
          _retry = null;
        }
        return;
      }
      final waited = DateTime.now().difference(_queuedAt!);
      if (!splashDone && waited < _maxWait) return;
      _retry?.cancel();
      _retry = null;
      _pending = null;
      key.currentState?.pushNamed(
        pending['route'] as String,
        arguments: pending['arguments'],
      );
    });
  }
}
