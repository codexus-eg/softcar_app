import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../core/utils/egypt_map_style.dart' show lerpAngle;

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

/// Rotated vehicle marker for the driver's own car or a tracked shuttle.
Marker vehicleSpriteMarker({
  required LatLng point,
  required int seats,
  double bearingDeg = 0,
  double? width,
}) {
  final size = Size(width ?? spriteSizeForSeats(seats).width, 0);
  final h = size.width * (seats <= 4 ? 118 / 64 : 132 / 74);
  return Marker(
    point: point,
    width: size.width + 14,
    height: h + 14,
    child: _Shadowed(
      bearingRad: bearingDeg * math.pi / 180,
      asset: spriteAssetForSeats(seats),
    ),
  );
}

class _Shadowed extends StatelessWidget {
  const _Shadowed({required this.bearingRad, required this.asset});

  final double bearingRad;
  final String asset;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Transform.rotate(
          angle: bearingRad,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              boxShadow: [
                BoxShadow(color: Color(0x73000000), blurRadius: 10, offset: Offset(0, 4)),
              ],
            ),
            child: Image.asset(asset, fit: BoxFit.contain),
          ),
        ),
      ],
    );
  }
}

/// Gentle bobbing human figure. genderCode: 'MALE'|'FEMALE'|'M'|'F'|null(male).
Marker humanSpriteMarker(LatLng point, String? genderCode, {double scale = 1}) {
  final female = ['FEMALE', 'F'].contains(genderCode?.toUpperCase());
  return Marker(
    point: point,
    width: 30 * scale,
    height: 38 * scale,
    child: _Bobbing(asset: female ? 'assets/map/human_female.png' : 'assets/map/human_male.png'),
  );
}

class _Bobbing extends StatefulWidget {
  const _Bobbing({required this.asset});
  final String asset;

  @override
  State<_Bobbing> createState() => _BobbingState();
}

class _BobbingState extends State<_Bobbing> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => Transform.translate(
        offset: Offset(0, -3 * _c.value),
        child: Opacity(opacity: 0.92, child: Image.asset(widget.asset)),
      ),
    );
  }
}

/// Creates a smooth-interpolated [Marker] for a vehicle that may be moving.
///
/// Call this from a [MarkerLayer] and pass the same [from] and [to] positions
/// plus the animation [t] (0→1) so the caller controls the interpolation.
Marker animatedVehicleMarker({
  required LatLng from,
  required LatLng to,
  required double t,
  required int seats,
  required double fromBearing,
  required double toBearing,
  double width = 42,
}) {
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
    width: width,
  );
}

/// Standing / parked vehicle marker with slight desaturation.
///
/// Used for decorative stop-point markers during IN_PROGRESS trips.
Marker standingVehicleMarker({
  required LatLng point,
  required int seats,
  double bearingDeg = 0,
  double width = 30,
}) {
  final size = Size(width, 0);
  final h = size.width * (seats <= 4 ? 118 / 64 : 132 / 74);
  return Marker(
    point: point,
    width: size.width + 14,
    height: h + 14,
    child: Opacity(
      opacity: 0.85,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Transform.rotate(
            angle: bearingDeg * math.pi / 180,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                boxShadow: [
                  BoxShadow(color: Color(0x40000000), blurRadius: 6, offset: Offset(0, 3)),
                ],
              ),
              child: Image.asset(
                spriteAssetForSeats(seats),
                fit: BoxFit.contain,
                color: Colors.grey.shade400,
                colorBlendMode: BlendMode.saturation,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Crowd counter chip: small rounded badge showing passenger count near the
/// vehicle marker. Composed as a regular widget, not a bitmap.
class CrowdCounterChip extends StatelessWidget {
  final int onboard;
  const CrowdCounterChip({super.key, required this.onboard});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('👥', style: TextStyle(fontSize: 11)),
          const SizedBox(width: 2),
          Text(
            '$onboard',
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}
