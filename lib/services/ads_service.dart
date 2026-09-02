import 'package:flutter/foundation.dart';

import 'passenger_api.dart';

/// One home-screen ad from `GET /api/mobile/ads`. `imageUrl` is a
/// server-relative path and is resolved through [Formatters.imageUrl].
class AdItem {
  final String id;
  final String name;
  final String imageUrl;
  final String details;

  /// Optional backend hint for which animation to play (`fade`, `pulse`…
  /// or `fireworks`, `confetti`, `sparkle`, `shimmer`, `float`, `rotate`,
  /// `shake`).
  final String animation;

  /// Event rules / conditions text (free-form, may contain newlines).
  final String rules;

  /// How the event hero animates when it first opens (`fade`,
  /// `slide_up`…). The named page transition on the event viewer.
  final String transition;

  /// Optional branding hex (`#FF5733`) used to tint the event hero.
  final String accentColor;

  /// True when this ad is a "focused event" that should show once as a forced
  /// overlay when the app opens (`isFocused` from the API).
  final bool isFocused;

  /// Media type: `IMAGE` or `VIDEO`.
  final String mediaType;

  /// Direct URL for `VIDEO` ads (opened in the device browser/player).
  final String videoUrl;

  /// Seconds a `VIDEO` ad should play/display before it may be skipped.
  final int displaySeconds;

  const AdItem({
    required this.id,
    required this.name,
    this.imageUrl = '',
    this.details = '',
    this.animation = '',
    this.rules = '',
    this.transition = 'fade',
    this.accentColor = '',
    this.isFocused = false,
    this.mediaType = 'IMAGE',
    this.videoUrl = '',
    this.displaySeconds = 8,
  });

  factory AdItem.fromJson(Map<String, dynamic> json) => AdItem(
    id: json['id']?.toString() ?? '',
    name: json['name']?.toString() ?? '',
    imageUrl: json['imageUrl']?.toString() ?? '',
    details: json['details']?.toString() ?? '',
    animation: json['animation']?.toString() ?? '',
    rules: json['rules']?.toString() ?? '',
    transition: json['transition']?.toString() ?? 'fade',
    accentColor: json['accentColor']?.toString() ?? '',
    isFocused: json['isFocused'] == true || json['isFocused'] == 'true',
    mediaType: json['mediaType']?.toString() ?? 'IMAGE',
    videoUrl: json['videoUrl']?.toString() ?? '',
    displaySeconds: (json['displaySeconds'] as num?)?.toInt() ?? 8,
  );
}

/// Fetches and caches the home-screen ads carousel. Network failures are
/// swallowed so the home screen cleanly falls back to the plan-your-ride
/// placeholder instead of breaking.
class AdsService extends ChangeNotifier {
  List<AdItem> _ads = const [];
  bool _loading = false;
  Object? _error;

  List<AdItem> get ads => _ads;
  bool get loading => _loading;
  Object? get error => _error;

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final rows = await passengerApi.getAds();
      _ads =
          rows
              .whereType<Map>()
              .map((e) => AdItem.fromJson(Map<String, dynamic>.from(e)))
              .toList();
    } catch (e) {
      _error = e;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}
