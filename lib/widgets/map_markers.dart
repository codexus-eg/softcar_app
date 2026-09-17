import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gm;
import 'package:latlong2/latlong.dart';

import 'google_map_kit.dart';

/// Vehicle sprite per physical seat count (matches fleet classes).
String spriteAssetForSeats(int seats) {
  if (seats <= 4) return 'assets/map/sedan_3d.png';
  if (seats <= 14) return 'assets/map/hiace_14_3d.png';
  return 'assets/map/coaster_28_3d.png';
}

Size spriteSizeForSeats(int seats) {
  if (seats <= 4) return const Size(34, 62);
  if (seats <= 14) return const Size(40, 70);
  return const Size(40, 70);
}

final Map<int, gm.BitmapDescriptor> _vehicleIcons = {};

/// Loads (and caches) the 3D vehicle sprite for [seats] as a marker icon.
Future<gm.BitmapDescriptor> vehicleIconForSeats(int seats) async {
  final cached = _vehicleIcons[seats];
  if (cached != null) return cached;
  final spriteSize = spriteSizeForSeats(seats);
  final icon = await gm.BitmapDescriptor.asset(
    const ImageConfiguration(),
    spriteAssetForSeats(seats),
    width: spriteSize.width,
    height: spriteSize.height,
  );
  _vehicleIcons[seats] = icon;
  return icon;
}

/// Rotated vehicle marker for a driver's own car or a tracked shuttle.
Future<gm.Marker> vehicleSpriteMarker({
  required LatLng point,
  required int seats,
  double bearingDeg = 0,
  String id = 'vehicle',
}) async {
  final icon = await vehicleIconForSeats(seats);
  return gm.Marker(
    markerId: gm.MarkerId(id),
    position: toGm(point),
    icon: icon,
    rotation: bearingDeg,
    anchor: const Offset(0.5, 0.5),
    zIndexInt: 20,
  );
}

/// "You are here" marker drawn from the passenger's live position.
Future<gm.Marker> userDotMarker(
  LatLng point, {
  Color? color,
  String id = 'me',
}) async {
  final icon = await userDot(color ?? const Color(0xFF1E88E5));
  return gm.Marker(
    markerId: gm.MarkerId(id),
    position: toGm(point),
    icon: icon,
    anchor: const Offset(0.5, 0.5),
    zIndexInt: 30,
  );
}

/// Coloured bus stop on the route: origin / destination / intermediate.
Future<gm.Marker> stopMarker(
  int index,
  LatLng point, {
  required int total,
  required Color accent,
  Color? wayColor,
  double bearingDeg = 0,
}) async {
  final icon = index == 0
      ? await originDot(accent)
      : index == total - 1
          ? await destinationPin(accent)
          : await waypointDot(wayColor ?? const Color(0xFF9AA3AB));
  return gm.Marker(
    markerId: gm.MarkerId('stop-$index'),
    position: toGm(point),
    icon: icon,
    rotation: bearingDeg,
    anchor: Offset(0.5, index == total - 1 ? 0.95 : 0.5),
    zIndexInt: 2,
  );
}

double lerpAngle(double a, double b, double t) {
  final diff = (b - a + 540) % 360 - 180;
  return a + diff * t;
}

/// A smooth-interpolated vehicle marker between [from] and [to] at animation
/// progress [t] (0→1). Used while the bus moves between GPS fixes.
Future<gm.Marker> animatedVehicleMarker({
  required LatLng from,
  required LatLng to,
  required double t,
  required int seats,
  required double fromBearing,
  required double toBearing,
  String id = 'vehicle',
}) async {
  final curve = Curves.easeOut.transform(t.clamp(0.0, 1.0));
  final pos = LatLng(
    from.latitude + (to.latitude - from.latitude) * curve,
    from.longitude + (to.longitude - from.longitude) * curve,
  );
  final bearing = lerpAngle(fromBearing, toBearing, curve);
  return vehicleSpriteMarker(
    point: pos,
    seats: seats,
    bearingDeg: bearing,
    id: id,
  );
}