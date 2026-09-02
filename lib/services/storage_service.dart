import 'package:shared_preferences/shared_preferences.dart';

/// Thin wrapper around SharedPreferences so call sites don't depend on
/// the plugin directly and values are easy to mock / change.
class StorageService {
  static const _kOnboarded = 'onboarded_v1';
  static const _kDarkMode = 'dark_mode_v1';
  static const _kLanguage = 'language_v1';
  static const _kSeen = 'notifications_seen_v1';

  Future<SharedPreferences?> _preferences() async {
    try {
      return await SharedPreferences.getInstance().timeout(
        const Duration(seconds: 3),
      );
    } catch (_) {
      return null;
    }
  }

  Future<bool> isOnboarded() async {
    final p = await _preferences();
    return p?.getBool(_kOnboarded) ?? false;
  }

  Future<void> setOnboarded() async {
    final p = await _preferences();
    await p?.setBool(_kOnboarded, true);
  }

  Future<String> getLanguage() async {
    final p = await _preferences();
    return p?.getString(_kLanguage) ?? 'en';
  }

  Future<void> setLanguage(String code) async {
    final p = await _preferences();
    await p?.setString(_kLanguage, code);
  }

  Future<bool> getDarkMode() async {
    final p = await _preferences();
    return p?.getBool(_kDarkMode) ?? false;
  }

  Future<void> setDarkMode(bool value) async {
    final p = await _preferences();
    await p?.setBool(_kDarkMode, value);
  }

  Future<bool> notificationsSeen() async {
    final p = await _preferences();
    return p?.getBool(_kSeen) ?? false;
  }

  Future<void> markNotificationsSeen() async {
    final p = await _preferences();
    await p?.setBool(_kSeen, true);
  }

  // Completed-trip log ----------------------------------------------------
  static const _kTrips = 'trips_log_v1';

  Future<List<String>> getTripLog() async {
    final p = await _preferences();
    return p?.getStringList(_kTrips) ?? [];
  }

  Future<void> addTripLog(String entry) async {
    final p = await _preferences();
    if (p == null) return;
    final list = p.getStringList(_kTrips) ?? [];
    list.insert(0, entry);
    if (list.length > 50) list.removeRange(50, list.length);
    await p.setStringList(_kTrips, list);
  }

  // Voucher codes the user has already seen/dismissed ---------------------
  static const _kSeenVouchers = 'vouchers_seen_v1';

  Future<List<String>> getSeenVouchers() async {
    final p = await _preferences();
    return p?.getStringList(_kSeenVouchers) ?? [];
  }

  Future<void> markVoucherSeen(String code) async {
    final p = await _preferences();
    if (p == null) return;
    final list = p.getStringList(_kSeenVouchers) ?? [];
    if (!list.contains(code)) {
      list.add(code);
      await p.setStringList(_kSeenVouchers, list);
    }
  }

  // Focused-event ad ids the user has already dismissed -------------------
  static const _kSeenFocusAds = 'focus_ads_seen_v1';

  Future<List<String>> getSeenFocusAds() async {
    final p = await _preferences();
    return p?.getStringList(_kSeenFocusAds) ?? [];
  }

  Future<void> markFocusAdSeen(String id) async {
    final p = await _preferences();
    if (p == null) return;
    final list = p.getStringList(_kSeenFocusAds) ?? [];
    if (!list.contains(id)) {
      list.add(id);
      await p.setStringList(_kSeenFocusAds, list);
    }
  }
}
