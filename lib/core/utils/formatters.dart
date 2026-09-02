import 'dart:math' as math;

import 'package:intl/intl.dart';

import 'egypt_time.dart';

/// Formatting helpers shared across the app.
class Formatters {
  Formatters._();

  static final NumberFormat _money = NumberFormat.currency(
    symbol: 'EGP ',
    decimalDigits: 2,
  );

  static final NumberFormat _moneyWhole = NumberFormat.currency(
    symbol: 'EGP ',
    decimalDigits: 0,
  );

  static String money(num value) => _money.format(value);

  static String moneyWhole(num value) => _moneyWhole.format(value);

  /// Compact EGP amount, e.g. `114` → "EGP 114" and `114.5` → "EGP 114.50".
  static String currency(num value) {
    final formatted =
        value == value.roundToDouble()
            ? value.toInt().toString()
            : value.toStringAsFixed(2);
    return 'EGP $formatted';
  }

  /// Formats seconds (a duration) as "5 min" or "1 hr 05 min".
  static String minutes(int minutes) {
    if (minutes < 60) return '$minutes min';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '$h hr' : '$h hr ${m.toString().padLeft(2, '0')} min';
  }

  static String distanceKm(double km) {
    if (km < 1) return '${(km * 1000).round()} m';
    return '${km.toStringAsFixed(km < 10 ? 1 : 0)} km';
  }

  static String greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  static String shortDate(DateTime dt) {
    return DateFormat('MMM d').format(dt);
  }

  /// Resolves a server-relative image path to a full URL. Absolute URLs are
  /// returned untouched; relative paths are prefixed with the production host.
  static String imageUrl(String? path) {
    if (path == null || path.isEmpty) return '';
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    return 'https://softcarshuttle.com$path';
  }

  static String relative(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hr ago';
    if (diff.inDays < 7) return '${diff.inDays} d ago';
    return shortDate(egDate(dt)!);
  }

  /// Haversine distance between two coordinates in km (numeric).
  static double haversineKm(
      double lat1, double lng1, double lat2, double lng2) {
    const r = 6371.0;
    final dLat = _rad(lat2 - lat1);
    final dLng = _rad(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(lat1)) *
            math.cos(_rad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c;
  }

  static String distanceBetweenKm(double lat1, double lng1, double lat2,
      double lng2) {
    return distanceKm(haversineKm(lat1, lng1, lat2, lng2));
  }

  static double _rad(double deg) => deg * math.pi / 180.0;
}
