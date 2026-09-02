import 'dart:async';
import 'dart:io' show Platform;

import 'dart:convert';

import 'dart:ui' show Color;

import 'package:flutter/widgets.dart' show WidgetsFlutterBinding;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../core/utils/app_nav.dart';
import 'auth_service.dart';
import 'passenger_api.dart';

/// Loud push notifications via flutter_local_notifications (no Firebase
/// required). The channel plays the bundled `passenger_notification_tone`
/// (a dedicated SoftCar passenger tone at res/raw/passenger_notification_tone.mp3 —
/// never a device ringtone) on the ALARM audio stream at maximum importance,
/// so booking/trip alerts are very loud even when the app is closed. A
/// Workmanager periodic task keeps polling `GET /notifications` after the
/// app has been swiped away and raises loud tray notifications.
class PushService {
  PushService._();

  static final PushService instance = PushService._();

  // v2 suffix forces Android to recreate the channel on upgraded installs —
  // an existing channel's sound/importance can never be mutated in place.
  static const _channelId = 'softcar-loud-v3';
  static const _channelName = 'SoftCar loud alerts';
  static const _channelDesc = 'Booking, trip and support alerts';
  static const _fcmChannelId = 'high_importance_channel';
  static const _seenKey = 'softcar.loud.seen';
  static const _taskName = 'softcarNotifPoll';
  static const _tokenKey = 'softcar.passenger.token';
  static const _exactAskedKey = 'softcar.exact.alarms.asked';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;

  /// Last known FCM/Expo push token. Set by the caller once FCM is
  /// initialised; persists across hot-restarts via SharedPreferences.
  static const _fcmTokenKey = 'softcar.passenger.fcmToken';
  static String? _currentPushToken;

  /// Initializes the plugin and creates the loud notification channel.
  ///
  /// [requestRuntimePermissions] must only be true for foreground UI boots:
  /// it raises the POST_NOTIFICATIONS / exact-alarm system prompts and reads
  /// the cold-start launch details. The headless background isolate calls
  /// this with the default `false`.
  Future<void> init({bool requestRuntimePermissions = false}) async {
    if (_ready) return;
    try {
      WidgetsFlutterBinding.ensureInitialized();
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const ios = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      await _plugin.initialize(
        const InitializationSettings(android: android, iOS: ios),
        onDidReceiveNotificationResponse: _handleTap,
        onDidReceiveBackgroundNotificationResponse:
            _passengerBackgroundTapHandler,
      );
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              _channelId,
              _channelName,
              description: _channelDesc,
              importance: Importance.max,
              playSound: true,
              sound: RawResourceAndroidNotificationSound('passenger_notification_tone'),
              enableVibration: true,
              enableLights: true,
              ledColor: Color(0xFFFF3B30),
              audioAttributesUsage: AudioAttributesUsage.alarm,
            ),
          );
      // FCM display channel: the backend sends Firebase display messages
      // targeting this exact id; without a matching channel Android silently
      // drops tray notifications while the app is killed.
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              _fcmChannelId,
              _channelName,
              description: _channelDesc,
              importance: Importance.max,
              playSound: true,
              sound: RawResourceAndroidNotificationSound(
                  'passenger_notification_tone'),
              enableVibration: true,
              enableLights: true,
              ledColor: Color(0xFFFF3B30),
              audioAttributesUsage: AudioAttributesUsage.alarm,
            ),
          );
      if (!requestRuntimePermissions) {
        _ready = true;
        return;
      }
      await requestPermission();
      try {
        final launch = await _plugin.getNotificationAppLaunchDetails();
        if (launch?.didNotificationLaunchApp ?? false) {
          _handleTap(launch!.notificationResponse);
        }
      } catch (_) {}
      _ready = true;
    } catch (_) {
      // Notifications are best-effort; never crash on failure.
    }
  }

  /// Requests notification permission on Android 13+ / iOS, plus the Android
  /// 12+ "alarms & reminders" grant once (needed for heads-up full-screen
  /// alerts on some OEM builds). Failures are silent.
  Future<bool> requestPermission() async {
    var granted = true;
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      final androidOk = await android?.requestNotificationsPermission();
      final iosOk = await ios?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      granted = androidOk ?? iosOk ?? true;
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!(prefs.getBool(_exactAskedKey) ?? false)) {
        await prefs.setBool(_exactAskedKey, true);
        final android = _plugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>();
        if (await android?.canScheduleExactNotifications() == false) {
          await android?.requestExactAlarmsPermission();
        }
      }
    } catch (_) {}
    return granted;
  }

  /// Returns the last known push token (FCM or Expo), or null if none.
  static String? get currentPushToken => _currentPushToken;

  /// Stores the push token so it can be registered on login and unregistered
  /// on sign-out. Call this once FCM is initialised and the token is known.
  static Future<void> setPushToken(String? token) async {
    _currentPushToken = token;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (token == null || token.isEmpty) {
        await prefs.remove(_fcmTokenKey);
      } else {
        await prefs.setString(_fcmTokenKey, token);
      }
    } catch (_) {}
  }

  /// Restores the persisted push token on cold start.
  static Future<void> restorePushToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _currentPushToken = prefs.getString(_fcmTokenKey);
    } catch (_) {}
  }

  /// Maps a server notification row/type to the screen that shows the related
  /// workflow (kept in sync with NotificationsScreen._linkFor). Falls back to
  /// the home tab when no clear target exists.
  static String routeForType(String type) {
    final t = type.toUpperCase();
    if (t.contains('VOIP') || t.contains('SOFT_CALL')) return '/incoming-call';
    if (t.contains('EVENT')) return '/notifications';
    if (t.contains('BOARDING') ||
        t.contains('ARRIVING') ||
        t.contains('STARTING') ||
        t.contains('RESERVATION') ||
        t.contains('TRIP') ||
        t.contains('BOOKING') ||
        t.contains('SHUTTLE') ||
        t.contains('NO_SHOW') ||
        t.contains('NOT_COMING') ||
        t.contains('BOARDED') ||
        t.contains('DROPPED')) {
      return '/boarding-confirmation';
    }
    if (t.contains('RECHARGE') ||
        t.contains('WALLET') ||
        t.contains('PAYMENT') ||
        t.contains('REFUND') ||
        t.contains('CARD') ||
        t.contains('BALANCE')) {
      return '/wallet';
    }
    if (t.contains('SUPPORT') || t.contains('TICKET')) return '/support-tickets';
    return '/home';
  }

  void _handleTap(NotificationResponse? response) {
    final payload = response?.payload;
    if (payload == null || payload.isEmpty) {
      AppNav.go('/notifications');
      return;
    }
    var type = '';
    try {
      final data = jsonDecode(payload);
      if (data is Map<String, dynamic>) type = data['type']?.toString() ?? '';
    } catch (_) {}
    AppNav.go(routeForType(type));
  }

  /// Platform-specific details shared by every alert: max importance/priority,
  /// raw `passenger_notification_tone` on the ALARM stream, vibration and a
  /// full-screen intent so boarding/trip alerts wake the screen even when
  /// locked.
  NotificationDetails details() => NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          importance: Importance.max,
          priority: Priority.max,
          playSound: true,
          sound: RawResourceAndroidNotificationSound('passenger_notification_tone'),
          enableVibration: true,
          fullScreenIntent: true,
          category: AndroidNotificationCategory.alarm,
          audioAttributesUsage: AudioAttributesUsage.alarm,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
          presentBadge: true,
          sound: 'passenger_notification_tone',
          interruptionLevel: InterruptionLevel.timeSensitive,
        ),
      );

  /// Shows a loud local notification immediately (used for booking
  /// confirmations and trip reminders). [payload] carries
  /// `{type,id}` JSON so tapping the alert can deep-link.
  Future<void> show({
    required String title,
    required String body,
    int id = 0,
    String? payload,
  }) async {
    try {
      await _plugin.show(id, title, body, details(), payload: payload);
    } catch (_) {}
  }

  // ---- background + closed-app polling --------------------------------------

  /// Registers the Workmanager periodic task that keeps polling backend
  /// notifications after the app has been closed from recents.
  Future<void> registerBackgroundPoll() async {
    try {
      await Workmanager().registerPeriodicTask(
        'softcar-notif-periodic',
        _taskName,
        frequency: const Duration(minutes: 15),
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingWorkPolicy.keep,
      );
    } catch (_) {}
  }

  /// One poll pass: fetches `/notifications` with the persisted token and
  /// raises a loud tray alert for every row not seen before. Safe to run in
  /// the foreground timer or the background isolate.
  static Future<bool> pollOnce() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(_tokenKey);
      if (token == null || token.isEmpty) return false;
      final res = await http.get(
        Uri.parse(
            'https://softcarshuttle.com/api/mobile/notifications?limit=20'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode != 200) return false;
      final json = jsonDecode(res.body);
      if (json is! Map<String, dynamic>) return false;
      final raw = json['notifications'] ?? json['data'];
      if (raw is! List) return false;
      final rows = [
        for (final item in raw)
          if (item is Map) Map<String, dynamic>.from(item),
      ];
      final seen = (prefs.getStringList(_seenKey) ?? const []).toSet();
      final nowSeen = <String>[];
      final fresh = <Map<String, dynamic>>[];
      for (final n in rows.reversed) {
        final id = n['id']?.toString() ?? '';
        if (id.isEmpty || seen.contains(id)) continue;
        nowSeen.add(id);
        fresh.add(n);
      }
      if (fresh.length == 1) {
        final n = fresh.first;
        final id = n['id']?.toString() ?? '';
        await instance.show(
          id: id.hashCode & 0x7fffffff,
          title: n['title']?.toString() ?? n['type']?.toString() ?? 'SoftCar',
          body: n['message']?.toString() ??
              n['body']?.toString() ??
              n['data']?.toString() ??
              '',
          payload: jsonEncode(<String, String>{
            'type': n['type']?.toString() ?? '',
            'id': id,
          }),
        );
      } else if (fresh.length > 1) {
        // Never flood the tray with a backlog of queued rows: collapse them
        // into one summary alert pointing at a relevant route.
        final latest = fresh.first;
        final ar = prefs.getString('language_v1') == 'ar';
        await instance.show(
          id: 'softcarBatchNotice'.hashCode & 0x7fffffff,
          title: 'SoftCar',
          body: ar
              ? 'لديك ${fresh.length} إشعارات جديدة'
              : 'You have ${fresh.length} new notifications',
          payload: jsonEncode(<String, String>{
            'type': latest['type']?.toString() ?? '',
            'id': '',
          }),
        );
      }
      if (nowSeen.isNotEmpty) {
        final merged = <String>{...(prefs.getStringList(_seenKey) ?? const <String>[]), ...nowSeen}
            .toList();
        final trimmed = merged.length > 100
            ? merged.sublist(merged.length - 100)
            : merged;
        await prefs.setStringList(_seenKey, trimmed);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Whether a backend notification row has already been surfaced on this
  /// install, so the real-time FCM path and the polling path never double
  /// alert the same notification.
  static Future<bool> isShown(String id) async {
    if (id.isEmpty) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      return (prefs.getStringList(_seenKey) ?? const []).contains(id);
    } catch (_) {
      return false;
    }
  }

  /// Marks a backend notification row as surfaced ([isShown] then returns
  /// true), so later FCM banners and polls skip it.
  static Future<void> markShown(String id) async {
    if (id.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final merged = <String>{
        ...(prefs.getStringList(_seenKey) ?? const <String>[]),
        id,
      }.toList();
      final trimmed = merged.length > 100
          ? merged.sublist(merged.length - 100)
          : merged;
      await prefs.setStringList(_seenKey, trimmed);
    } catch (_) {}
  }

  /// Registers the passenger's push device token with the backend. Expo push
  /// tokens are sent as-is; raw FCM tokens are sent with isExpoPushToken
  /// false. Failures are swallowed — the app must keep working offline.
  Future<void> registerDeviceToken({
    required AuthService auth,
    String? expoToken,
    String? fcmToken,
  }) async {
    if (!auth.isLoggedIn) return;
    try {
      final token = expoToken ?? fcmToken;
      if (token == null || token.isEmpty) return;
      await passengerApi.registerPushDevice(
        token: token,
        platform: Platform.isIOS ? 'ios' : 'android',
        deviceName: 'SoftCar Passenger',
        isExpoPushToken: expoToken != null,
      );
    } catch (_) {
      // Best-effort registration.
    }
  }

  /// Unregisters a device token on sign-out.
  Future<void> unregisterDeviceToken(String token) async {
    if (token.isEmpty) return;
    try {
      await passengerApi.unregisterPushDevice(token);
    } catch (_) {}
  }
}

/// Background tap entry point: while the engine is alive but the UI is
/// backgrounded, route through the app nav; cold-start taps are read from
/// the launch details in [PushService.init].
@pragma('vm:entry-point')
void _passengerBackgroundTapHandler(NotificationResponse details) {
  final payload = details.payload;
  if (payload == null || payload.isEmpty) {
    AppNav.go('/notifications');
    return;
  }
  var type = '';
  try {
    final data = jsonDecode(payload);
    if (data is Map<String, dynamic>) type = data['type']?.toString() ?? '';
  } catch (_) {}
  AppNav.go(PushService.routeForType(type));
}

/// Entry point for the Workmanager background isolate — keeps loud
/// notification polling alive after the app has been swiped away. The
/// binding must be initialized before any plugin call in this isolate.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      await PushService.instance.init();
      return await PushService.pollOnce();
    } catch (_) {
      return true;
    }
  });
}
