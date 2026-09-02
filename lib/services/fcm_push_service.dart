import 'dart:async';

import 'dart:convert';

import 'dart:typed_data';

import 'dart:ui' show Color;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart' show WidgetsFlutterBinding;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;

import 'passenger_api.dart';

/// FCM channel id — MUST match the backend message payload created in the
/// backend's `lib/fcm.ts` (android.notification.channel_id). It plays the
/// system default sound at maximum importance so a killed app still shows a
/// heads-up tray notification.
const kFcmChannelId = 'high_importance_channel';

/// Normalized FCM payload consumed by the app UI. `data` mirrors the backend
/// `{type,id,actionUrl,imageUrl}` fields so every alert can deep-link to the
/// right screen after the app is opened from the tray.
class FcmPushMessage {
  const FcmPushMessage({
    required this.title,
    required this.body,
    this.data = const {},
  });

  final String title;
  final String body;
  final Map<String, String> data;

  String get type => data['type'] ?? '';
  String get id => data['id'] ?? '';

  bool get isVoice => type.contains('VOIP') || type.contains('SOFT_CALL');

  /// Public image URL attached by the sender (used for the big-picture style).
  String get imageUrl => data['imageUrl'] ?? '';

  factory FcmPushMessage.fromRemoteMessage(RemoteMessage message) {
    final notification = message.notification;
    return FcmPushMessage(
      title: notification?.title ?? message.data['title'] ?? 'SoftCar',
      body: notification?.body ?? message.data['body'] ?? '',
      data: Map<String, String>.from(message.data),
    );
  }

  factory FcmPushMessage.fromDataPayload(String payload) {
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map<String, dynamic>) {
        return FcmPushMessage(
          title: decoded['title']?.toString() ?? 'SoftCar',
          body: decoded['body']?.toString() ?? '',
          data: Map<String, String>.from(
            decoded.map((key, value) => MapEntry(key, value?.toString() ?? '')),
          ),
        );
      }
    } catch (_) {}
    return const FcmPushMessage(title: 'SoftCar', body: '');
  }

  Map<String, String> toDataPayload() => {
        'type': type,
        'id': id,
        if (title.isNotEmpty) 'title': title,
        if (body.isNotEmpty) 'body': body,
        if (imageUrl.isNotEmpty) 'imageUrl': imageUrl,
      };
}

/// Entry point for the FCM background isolate (app swiped away / terminated).
/// Hybrid notification+data pushes are already shown in the tray by the OS,
/// but this handler guarantees a data-only push (or a notification that the
/// OS delayed) still raises a local notification in the background isolate.
@pragma('vm:entry-point')
Future<void> fcmBackgroundHandler(RemoteMessage message) async {
  try {
    if (message.data['type'] == 'E2E_TEST') return;
    WidgetsFlutterBinding.ensureInitialized();
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
    );
    await FcmPushService._ensureChannel(plugin);
    final fcm = FcmPushMessage.fromRemoteMessage(message);
    final details = await FcmPushService._bannerDetails(fcm);
    await plugin.show(
      FcmPushService._idFor(fcm),
      fcm.title,
      fcm.body,
      details,
      payload: jsonEncode(fcm.toDataPayload()),
    );
  } catch (_) {
    // FCM is best-effort; never let a background handler crash the isolate.
  }
}

/// One-stop FCM wiring: foreground banner, cold-start / background tap
/// deep-links, and token registration lifecycle. Everything degrades cleanly
/// when Firebase has not been configured (no google-services.json /
/// GoogleService-Info.plist yet): `init()` returns false and the apps keep
/// using their existing SSE + HTTP polling pipelines.
class FcmPushService {
  FcmPushService._();

  static final FcmPushService instance = FcmPushService._();

  bool _ready = false;
  bool _wired = false;
  String? _cachedToken;

  bool get ready => _ready;

  /// The most recent FCM token this isolate has seen, if any. Lets the auth
  /// layer re-register right after a later sign-in — the app-start
  /// registration is skipped while the user is logged out.
  static String? get cachedToken => instance._cachedToken;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  Future<void> _ensureLocalPlugin() async {
    try {
      await _plugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(),
        ),
        onDidReceiveNotificationResponse: _handleNotificationTap,
      );
      await _ensureChannel(_plugin);
    } catch (_) {}
  }

  static Future<void> _ensureChannel(FlutterLocalNotificationsPlugin plugin) async {
    try {
      await plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              kFcmChannelId,
              'SoftCar alerts',
              description: 'Trip, booking and support alerts',
              importance: Importance.max,
              playSound: true,
              enableVibration: true,
              enableLights: true,
              ledColor: Color(0xFF1AA78A),
            ),
          );
    } catch (_) {}
  }

  static Future<Uint8List?> _fetchImage(String url) async {
    try {
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        return response.bodyBytes;
      }
    } catch (_) {}
    return null;
  }

  static Future<NotificationDetails> _bannerDetails(FcmPushMessage message) async {
    final imageUrl = message.imageUrl;
    final imageBytes =
        (imageUrl.isEmpty) ? null : await _fetchImage(imageUrl);
    return NotificationDetails(
      android: AndroidNotificationDetails(
        kFcmChannelId,
        'SoftCar alerts',
        channelDescription: 'Trip, booking and support alerts',
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
        enableLights: true,
        category: AndroidNotificationCategory.recommendation,
        styleInformation: imageBytes == null
            ? null
            : BigPictureStyleInformation(
                ByteArrayAndroidBitmap(imageBytes),
                contentTitle: message.title,
                summaryText: message.body,
              ),
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentSound: true,
        presentBadge: true,
      ),
    );
  }

  static int _idFor(FcmPushMessage message) {
    final seed = message.id.hashCode ^ message.type.hashCode;
    return seed & 0x7fffffff;
  }

  /// Shows the foreground banner that replaces FCM's silent foreground
  /// delivery (FCM notification messages are NOT auto-displayed while the
  /// app is in the foreground).
  Future<void> showBanner(FcmPushMessage message) async {
    try {
      final details = await _bannerDetails(message);
      await _plugin.show(
        _idFor(message),
        message.title,
        message.body,
        details,
        payload: jsonEncode(message.toDataPayload()),
      );
    } catch (_) {}
  }

  void _handleNotificationTap(NotificationResponse? response) {
    final payload = response?.payload;
    if (payload == null || payload.isEmpty) return;
    final message = FcmPushMessage.fromDataPayload(payload);
    if (message.type.isEmpty) return;
    _onOpened?.call(message);
  }

  void Function(FcmPushMessage message)? _onOpened;
  Future<void> Function(String token)? _onToken;

  /// Initializes Firebase, registers the runtime permission + high-importance
  /// channel, wires foreground/tapped handlers and pushes the FCM token to
  /// [onToken] on first launch and every refresh afterwards.
  Future<bool> init({
    required void Function(FcmPushMessage message) onOpened,
    required Future<void> Function(String token) onToken,
  }) async {
    if (_wired) return _ready;

    try {
      await Firebase.initializeApp();
    } catch (_) {
      _wired = true;
      _ready = false;
      return false;
    }

    _onOpened = onOpened;
    _onToken = onToken;
    _wired = true;

    final messaging = FirebaseMessaging.instance;

    // Runtime permission (alert/badge/sound) — Android 13+ POST_NOTIFICATIONS
    // is also declared in AndroidManifest.xml; iOS prompts here.
    try {
      await messaging.requestPermission(alert: true, badge: true, sound: true);
    } catch (_) {}

    await _ensureLocalPlugin();

    // Foreground: FCM stays silent by design — raise a local banner instead.
    // The acknowledgement lets the ops dashboard measure true delivery.
    FirebaseMessaging.onMessage.listen((message) {
      if (_cachedToken != null && _cachedToken!.isNotEmpty) {
        unawaited(
          passengerApi
              .ackPush(_cachedToken!, notificationId: message.data['id'])
              .catchError((_) {}),
        );
      }
      showBanner(FcmPushMessage.fromRemoteMessage(message));
    });

    // Tapped while backgrounded (includes local banners shown above).
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _onOpened?.call(FcmPushMessage.fromRemoteMessage(message));
    });

    // Killed cold-start tap.
    try {
      final initial = await messaging.getInitialMessage();
      if (initial != null) {
        _onOpened?.call(FcmPushMessage.fromRemoteMessage(initial));
      }
    } catch (_) {}

    // Token lifecycle: register on launch/app start and whenever FCM rotates
    // the token. The backend auto-disables tokens that go stale.
    unawaited(_registerCurrentToken());
    messaging.onTokenRefresh.listen((token) {
      unawaited(_registerToken(token));
    });

    _ready = true;
    return true;
  }

  Future<void> _registerCurrentToken() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null && token.isNotEmpty) {
        _cachedToken = token;
        await _registerToken(token);
      }
    } catch (_) {}
  }

  Future<void> _registerToken(String token) async {
    _cachedToken = token;
    final handler = _onToken;
    if (handler == null) return;
    try {
      await handler(token);
    } catch (_) {}
  }
}