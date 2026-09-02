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
  final title = message.notification?.title ?? data['title']?.toString() ?? 'SoftCar';
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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  SoftCallBootstrap.init();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.white,
    ),
  );

  // Draw the first Flutter frame before invoking platform plugins. On some
  // cold Android starts the engine can run Dart a fraction before plugin
  // registration finishes; awaiting SharedPreferences here used to leave
  // the native logo on screen forever with MissingPluginException.
  final storage = StorageService();
  await PushService.restorePushToken();
  try {
    final fcmToken = await FirebaseMessaging.instance.getToken();
    if (fcmToken != null && fcmToken.isNotEmpty) {
      await PushService.setPushToken(fcmToken);
    }
    FirebaseMessaging.instance.onTokenRefresh.listen((refreshed) async {
      await PushService.setPushToken(refreshed);
    });
  } catch (_) {}
  FirebaseMessaging.onMessage.listen(_onFcmMessage);
  FirebaseMessaging.onBackgroundMessage(_onFcmBackgroundMessage);
  FirebaseMessaging.onMessageOpenedApp.listen(_onFcmOpened);
  runApp(SoftCarApp(
    storage: storage,
    initialDark: false,
    initialLocale: const Locale('en'),
  ));

  try {
    Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
  } catch (_) {}

  WidgetsBinding.instance.addPostFrameCallback((_) {
    // Foreground boot: also raises runtime prompts and resolves a cold-start
    // notification tap into a pending deep-link route.
    unawaited(PushService.instance.init(requestRuntimePermissions: true));
    try {
      FirebaseMessaging.instance.getInitialMessage().then((m) {
        if (m != null) _onFcmOpened(m);
      });
    } catch (_) {}
    PushService.instance.registerBackgroundPoll();
    Timer.periodic(const Duration(seconds: 30), (_) {
      PushService.pollOnce();
    });
  });
}
