import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:workmanager/workmanager.dart';

import 'app.dart';
import 'core/utils/app_nav.dart';
import 'services/push_service.dart';
import 'services/soft_call_bootstrap.dart';
import 'services/storage_service.dart';

Future<void> _onFcmMessage(RemoteMessage message) async {
  final data = message.data;
  final title =
      message.notification?.title ?? data['title']?.toString() ?? 'SoftCar';
  final body = message.notification?.body ?? data['body']?.toString() ?? '';
  final type = data['type']?.toString() ?? '';
  final id = data['id']?.toString() ?? data['notificationId']?.toString() ?? '';
  if (id.isNotEmpty && await PushService.isShown(id)) return;
  await PushService.instance.show(
    id: (id.isNotEmpty ? id : title).hashCode & 0x7fffffff,
    title: title,
    body: body,
    payload: jsonEncode(<String, String>{'type': type, 'id': id}),
  );
  if (id.isNotEmpty) await PushService.markShown(id);
}

@pragma('vm:entry-point')
Future<void> _onFcmBackgroundMessage(RemoteMessage message) async {
  // Background/killed messages show automatically in the system tray.
}

/// Background-tap / cold-start deep link from an FCM tray notification.
void _onFcmOpened(RemoteMessage message) {
  final data = message.data;
  final type = data['type']?.toString() ?? '';
  AppNav.go(PushService.routeForType(type));
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SoftCallBootstrap.init();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.white,
    ),
  );

  // Nothing above runApp may depend on an optional platform service. In
  // particular, Firebase cannot initialize on iOS until a valid
  // GoogleService-Info.plist has been added to the Runner target. Awaiting it
  // here used to stop Flutter before its first frame and leave the native
  // launch screen visible forever.
  final storage = StorageService();
  runApp(
    SoftCarApp(
      storage: storage,
      initialDark: false,
      initialLocale: const Locale('en'),
    ),
  );

  // Optional native integrations start only after Flutter has rendered. A
  // missing/misconfigured Firebase file or plugin can disable that feature,
  // but can no longer prevent passengers from opening the app.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(_startOptionalServices());
  });
}

/// Starts best-effort platform integrations without delaying the first frame.
///
/// Every awaited plugin call has a timeout and its own failure boundary. This
/// is important for App Store builds because Firebase is optional until the
/// developer supplies the bundle-specific GoogleService-Info.plist.
Future<void> _startOptionalServices() async {
  try {
    await PushService.restorePushToken().timeout(const Duration(seconds: 3));
  } catch (_) {}

  var firebaseReady = false;
  try {
    await Firebase.initializeApp().timeout(const Duration(seconds: 10));
    firebaseReady = true;
  } catch (_) {
    // The REST API, SSE and local polling continue to work without Firebase.
  }

  if (firebaseReady) {
    try {
      final fcmToken = await FirebaseMessaging.instance.getToken().timeout(
        const Duration(seconds: 8),
      );
      if (fcmToken != null && fcmToken.isNotEmpty) {
        await PushService.setPushToken(fcmToken);
      }
      FirebaseMessaging.instance.onTokenRefresh.listen((refreshed) {
        unawaited(PushService.setPushToken(refreshed));
      });
    } catch (_) {}

    FirebaseMessaging.onMessage.listen(_onFcmMessage);
    FirebaseMessaging.onBackgroundMessage(_onFcmBackgroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(_onFcmOpened);
    try {
      final initialMessage = await FirebaseMessaging.instance
          .getInitialMessage()
          .timeout(const Duration(seconds: 5));
      if (initialMessage != null) _onFcmOpened(initialMessage);
    } catch (_) {}
  }

  // Foreground boot: raises runtime prompts and prepares cold-start local
  // notification routing. This remains useful when Firebase is unavailable.
  try {
    await PushService.instance
        .init(requestRuntimePermissions: true)
        .timeout(const Duration(seconds: 10));
  } catch (_) {}

  try {
    await Workmanager()
        .initialize(callbackDispatcher, isInDebugMode: false)
        .timeout(const Duration(seconds: 10));
    await PushService.instance.registerBackgroundPoll();
  } catch (_) {}

  Timer.periodic(const Duration(seconds: 30), (_) {
    unawaited(PushService.pollOnce());
  });
}
