import 'package:flutter/material.dart';

import '../core/utils/app_nav.dart';
import 'passenger_api.dart';
import 'push_service.dart';
import 'soft_base_service.dart';
import 'voip_service.dart';

/// One-stop wiring for the Soft-Call stack in the passenger app:
///  * connects [VoipService] to the live REST contract,
///  * keeps a SoftBase SSE connection alive while signed in,
///  * turns `VOIP_RING` pushes into full-screen incoming-call cards
///    (foreground) or loud full-screen-intent notifications (background),
///  * funnels every other SoftBase frame through the existing loud
///    notification pipeline.
class SoftCallBootstrap {
  SoftCallBootstrap._();

  static bool _wired = false;

  /// Standalone wiring target for the VoIP engine.
  static void init() {
    if (_wired) return;
    _wired = true;
    VoipService.instance.wire(
      postSessions: passengerApi.voipPostSession,
      getSession: passengerApi.voipGetSession,
      sendSignal: passengerApi.voipSendSignal,
      getSignals: passengerApi.voipGetSignals,
    );
    SoftBaseService.instance.stream.listen(_onEvent);
  }

  /// Opens the realtime stream when a session token exists.
  static void connect() {
    init();
    final token = passengerApi.token;
    if (token != null && token.isNotEmpty) {
      SoftBaseService.instance.connect(token);
    }
  }

  /// Tears the realtime stream down (logout).
  static void disconnect() {
    SoftBaseService.instance.disconnect();
  }

  static void _onEvent(SoftBaseEvent event) {
    switch (event.type) {
      case 'VOIP_RING':
        _onRing(event);
        return;
      case 'E2E_TEST':
        return;
      default:
        // notification / promo / ad / event — reuse the loud pipeline.
        if (event.title.isEmpty && event.body.isEmpty) return;
        PushService.instance.show(
          title: event.title,
          body: event.body,
          payload: '{"type":"${event.type}","id":"${event.id}"}',
        );
        return;
    }
  }

  static void _onRing(SoftBaseEvent event) {
    final data = Map<String, dynamic>.from(event.data);
    final callId = _str(data, 'callSessionId') ?? '';
    if (callId.isEmpty) return;
    VoipService.instance.handleRing(data);

    final resumed =
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    if (resumed) {
      // Foreground: straight to the full-screen ringer.
      AppNav.go('/incoming-call');
    } else {
      // Background: wake the screen with a loud full-screen-intent alert;
      // tapping it routes to '/incoming-call' via PushService.routeForType.
      PushService.instance.show(
        title: _str(data, 'fromName') ?? 'SoftCar',
        body: 'Soft-Call',
        id: callId.hashCode & 0x7fffffff,
        payload: '{"type":"VOIP_RING","id":"$callId"}',
      );
    }
  }

  static String? _str(Map<String, dynamic> map, String key) =>
      map[key]?.toString();
}
