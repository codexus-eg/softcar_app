import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// App-wide singleton that owns the passenger's device location for the live
/// shuttle maps. It is intentionally lazy: nothing is started at boot. Screens
/// call [getSingleFix] for a one-shot high-accuracy fix ("locate me" buttons)
/// or [start]/[stop] to continuously follow the passenger as they move along
/// the route, updating [currentPosition] and notifying listeners.
class PassengerLocationService extends ChangeNotifier {
  PassengerLocationService._();

  /// Shared instance used by all live maps.
  static final PassengerLocationService instance =
      PassengerLocationService._();

  StreamSubscription<Position>? _subscription;
  LatLng? _currentPosition;

  /// Latest continuous fix, kept up to date while [start] is active.
  LatLng? get currentPosition => _currentPosition;

  /// Whether the continuous position stream is currently active.
  bool get isTracking => _subscription != null;

  /// Requests the while-in-use location permission when it has not been
  /// granted yet. Returns true once location access is available.
  Future<bool> ensurePermission() async {
    var granted = await _isGranted();
    if (!granted) {
      final requested = await Geolocator.requestPermission();
      granted = requested == LocationPermission.always ||
          requested == LocationPermission.whileInUse;
    }
    return granted;
  }

  Future<bool> _isGranted() async {
    try {
      final status = await Geolocator.checkPermission();
      return status == LocationPermission.always ||
          status == LocationPermission.whileInUse;
    } catch (_) {
      return false;
    }
  }

  /// Fetches a single high-accuracy fix and stores it as the current
  /// position. Returns null when the permission is denied or the fix fails.
  Future<LatLng?> getSingleFix() async {
    if (!await ensurePermission()) return null;
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
      _currentPosition = LatLng(pos.latitude, pos.longitude);
      notifyListeners();
      return _currentPosition;
    } catch (_) {
      return null;
    }
  }

  /// Starts following the passenger, updating [currentPosition] on every
  /// fix. Safe to call repeatedly — the underlying stream is opened once.
  Future<void> start() async {
    if (_subscription != null) return;
    if (!await ensurePermission()) return;
    _subscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen((pos) {
      _currentPosition = LatLng(pos.latitude, pos.longitude);
      notifyListeners();
    }, onError: (_) {
      // Keep the last known fix; a later update may recover.
    });
  }

  /// Stops the continuous position stream. Call from [dispose].
  void stop() {
    _subscription?.cancel();
    _subscription = null;
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
