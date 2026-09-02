import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../core/theme/app_colors.dart';

/// Blue "you are here" marker rendered on the live shuttle maps at the
/// passenger's position: a blue dot with a white ring and a subtle pulsing
/// outer halo. Stateless — call [toMarker] to add it to a [MarkerLayer].
class UserLocationMarker extends StatelessWidget {
  /// Where the passenger is on the map.
  final LatLng point;

  /// Diameter of the solid blue dot in logical pixels.
  final double size;

  const UserLocationMarker({super.key, required this.point, this.size = 26});

  /// Builds the [Marker] for use inside a [MarkerLayer].
  Marker toMarker() {
    final box = size * 1.9;
    return Marker(
      point: point,
      width: box,
      height: box,
      child: _UserLocationDot(size: size),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _UserLocationDot(size: size);
  }
}

/// The animated dot: a fixed blue centre ringed in white, with an expanding
/// translucent halo that fades out — the classic "you are here" pulse.
class _UserLocationDot extends StatefulWidget {
  final double size;
  const _UserLocationDot({required this.size});

  @override
  State<_UserLocationDot> createState() => _UserLocationDotState();
}

class _UserLocationDotState extends State<_UserLocationDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..repeat(reverse: false);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return SizedBox(
      width: s * 1.9,
      height: s * 1.9,
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, _) {
          final t = _pulse.value;
          return Center(
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Expanding halo which fades out as it grows.
                if (t < 0.85)
                  Container(
                    width: s * (1.0 + t * 0.9),
                    height: s * (1.0 + t * 0.9),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.info.withValues(alpha: 0.4 * (1 - t)),
                    ),
                  ),
                // Solid blue dot with a white ring.
                Container(
                  width: s,
                  height: s,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.info,
                    border: Border.all(color: Colors.white, width: 2.5),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Round floating "locate me" action used on the live maps to re-centre the
/// camera on the passenger. Shows a small spinner while [busy] is true.
class LocateMeButton extends StatelessWidget {
  final VoidCallback? onTap;
  final bool busy;
  final String tooltip;
  const LocateMeButton({
    super.key,
    required this.onTap,
    this.busy = false,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: dark ? AppColors.surfaceDarkElevated : Colors.white,
      shape: const CircleBorder(),
      elevation: 3,
      shadowColor: Colors.black.withValues(alpha: 0.28),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: busy ? null : onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.info),
                  )
                : Icon(
                    Icons.my_location,
                    color: AppColors.info,
                    size: 21,
                    semanticLabel: tooltip,
                  ),
          ),
        ),
      ),
    );
  }
}