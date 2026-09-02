import 'package:flutter/services.dart';

/// Centralized haptic feedback helpers. Light taps fire on primary actions
/// without cluttering the whole app.
class Haptics {
  static Future<void> light() => HapticFeedback.lightImpact();

  static Future<void> medium() => HapticFeedback.mediumImpact();

  static Future<void> heavy() => HapticFeedback.heavyImpact();

  static Future<void> selection() => HapticFeedback.selectionClick();

  static Future<void> success() => HapticFeedback.mediumImpact();

  static Future<void> deny() => HapticFeedback.vibrate();
}
