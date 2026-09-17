import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gm;
import 'package:latlong2/latlong.dart';

import '../core/l10n/l10n.dart';
import '../core/theme/app_colors.dart';
import '../services/passenger_location_service.dart';
import 'google_map_kit.dart';
import 'map_markers.dart';

/// Small circular "expand" control that floats over preview maps. Tapping
/// opens [FullscreenMapScreen] with the full set of map controls (map /
/// satellite / hybrid, traffic, my-location, fit route, zoom and pan).
class MapExpandButton extends StatelessWidget {
  final List<LatLng> points;
  final String originLabel;
  final String destinationLabel;
  const MapExpandButton({
    super.key,
    required this.points,
    required this.originLabel,
    required this.destinationLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: L10n.t(context, 'fullscreen'),
      child: Material(
        color: AppColors.accent.withValues(alpha: 0.12),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => openFullscreenMap(
            context,
            points: points,
            originLabel: originLabel,
            destinationLabel: destinationLabel,
          ),
          child: const Padding(
            padding: EdgeInsets.all(9),
            child: Icon(Icons.fullscreen_rounded, size: 20, color: AppColors.accent),
          ),
        ),
      ),
    );
  }
}

/// Pushes [FullscreenMapScreen] from the mini preview maps. Kept as a plain
/// function so both the seat-selection map and the live-bus card can open
/// the exact same fullscreen experience.
void openFullscreenMap(
  BuildContext context, {
  required List<LatLng> points,
  required String originLabel,
  required String destinationLabel,
}) {
  if (points.length < 2) return;
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => FullscreenMapScreen(
        points: points,
        originLabel: originLabel,
        destinationLabel: destinationLabel,
      ),
    ),
  );
}

/// Full-screen Google Map with all map controls: map / satellite / hybrid
/// styles, a traffic toggle, the "my-location" button, fit-route, native zoom
/// controls and free zoom/pan gestures. Used by the reservation route map and
/// the ticket's live-bus card.
class FullscreenMapScreen extends StatefulWidget {
  final List<LatLng> points;
  final String originLabel;
  final String destinationLabel;

  const FullscreenMapScreen({
    super.key,
    required this.points,
    required this.originLabel,
    required this.destinationLabel,
  });

  @override
  State<FullscreenMapScreen> createState() => _FullscreenMapScreenState();
}

class _FullscreenMapScreenState extends State<FullscreenMapScreen> {
  gm.GoogleMapController? _controller;
  gm.MapType _mapType = gm.MapType.normal;
  bool _traffic = false;
  bool _locating = false;
  bool _loaded = false;

  Set<gm.Marker> _stops = {};
  Set<gm.Marker> _markers = {};
  Set<gm.Polyline> _polylines = {};

  @override
  void initState() {
    super.initState();
    final location = PassengerLocationService.instance;
    location.addListener(_onLocationChanged);
    unawaited(location.start());
    _load();
  }

  Future<void> _load() async {
    final pts = widget.points;
    final accent = AppColors.accent;
    final stops = <gm.Marker>{};
    for (var i = 0; i < pts.length; i++) {
      stops.add(await stopMarker(i, pts[i], total: pts.length, accent: accent));
    }
    final polylines = await routePolylines(
      id: 'full-route',
      points: pts,
      color: AppColors.mapRoute,
    );
    if (!mounted) return;
    _stops = stops;
    _polylines = {...polylines};
    _loaded = true;
    await _applyMarkers();
  }

  /// Refreshes just the "you are here" marker when the device moves.
  Future<void> _applyMarkers() async {
    if (!_loaded) return;
    final pos = PassengerLocationService.instance.currentPosition;
    final markers = <gm.Marker>{..._stops};
    if (pos != null) markers.add(await userDotMarker(pos));
    if (!mounted) return;
    setState(() => _markers = markers);
  }

  void _onLocationChanged() {
    if (!mounted) return;
    setState(() {});
    _applyMarkers();
  }

  Future<void> _fit() async {
    final controller = _controller;
    if (controller == null) return;
    final pts = widget.points;
    final pos = PassengerLocationService.instance.currentPosition;
    await controller.moveCamera(
      cameraForBounds(
        pts,
        extra: pos == null ? null : [pos],
        padding: 60,
      ),
    );
  }

  Future<void> _locateMe() async {
    final location = PassengerLocationService.instance;
    setState(() => _locating = true);
    try {
      final pos = await location.getSingleFix();
      if (!mounted) return;
      if (pos == null) return;
      await _controller?.moveCamera(
        gm.CameraUpdate.newCameraPosition(
          gm.CameraPosition(target: toGm(pos), zoom: 16),
        ),
      );
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  void dispose() {
    final location = PassengerLocationService.instance;
    location.removeListener(_onLocationChanged);
    location.stop();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pts = widget.points;
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (pts.length >= 2)
            Positioned.fill(
              child: gm.GoogleMap(
                mapType: _mapType,
                trafficEnabled: _traffic,
                initialCameraPosition: gm.CameraPosition(
                  target: toGm(pts.first),
                  zoom: 12,
                ),
                onMapCreated: (c) {
                  _controller = c;
                  _fit();
                },
                markers: _markers,
                polylines: _polylines,
                style: _mapType == gm.MapType.normal ? googleMapStyle() : null,
                zoomControlsEnabled: true,
                compassEnabled: true,
                mapToolbarEnabled: true,
                myLocationButtonEnabled: true,
                myLocationEnabled: true,
                scrollGesturesEnabled: true,
                rotateGesturesEnabled: true,
                tiltGesturesEnabled: true,
                buildingsEnabled: true,
              ),
            ),
          // Top bar: exit fullscreen + route title.
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Container(
                margin: const EdgeInsets.all(10),
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color:
                      dark
                          ? AppColors.surfaceDarkElevated.withValues(alpha: 0.92)
                          : Colors.white.withValues(alpha: 0.94),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _MapControlButton(
                      tooltip: L10n.t(context, 'exitFullscreen'),
                      icon: Icons.fullscreen_exit_rounded,
                      onTap: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 4),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 220),
                      child: Text(
                        '${widget.originLabel} → ${widget.destinationLabel}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
              ),
            ),
          ),
          // Bottom control panel: map style, traffic, my location, fit route.
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                margin: const EdgeInsets.all(10),
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                decoration: BoxDecoration(
                  color:
                      dark
                          ? AppColors.surfaceDarkElevated.withValues(alpha: 0.92)
                          : Colors.white.withValues(alpha: 0.94),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        _MapTypeChip(
                          label: L10n.t(context, 'mapNormal'),
                          icon: Icons.map_rounded,
                          selected: _mapType == gm.MapType.normal,
                          onTap: () {
                            setState(() => _mapType = gm.MapType.normal);
                            _fit();
                          },
                        ),
                        const SizedBox(width: 6),
                        _MapTypeChip(
                          label: L10n.t(context, 'satellite'),
                          icon: Icons.satellite_alt_rounded,
                          selected: _mapType == gm.MapType.satellite,
                          onTap: () {
                            setState(() => _mapType = gm.MapType.satellite);
                            _fit();
                          },
                        ),
                        const SizedBox(width: 6),
                        _MapTypeChip(
                          label: L10n.t(context, 'hybrid'),
                          icon: Icons.layers_rounded,
                          selected: _mapType == gm.MapType.hybrid,
                          onTap: () {
                            setState(() => _mapType = gm.MapType.hybrid);
                            _fit();
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _ToggleChip(
                            label: L10n.t(context, 'traffic'),
                            icon: Icons.traffic_rounded,
                            active: _traffic,
                            onTap: () =>
                                setState(() => _traffic = !_traffic),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _ToggleChip(
                            label: L10n.t(context, 'fitRoute'),
                            icon: Icons.fit_screen_rounded,
                            active: false,
                            onTap: _fit,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _ToggleChip(
                            label: L10n.t(context, 'locateMe'),
                            icon: Icons.my_location_rounded,
                            active: _locating,
                            onTap: _locateMe,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Round tinted button used on the overlay bars (exit, my-location…).
class _MapControlButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  const _MapControlButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: AppColors.accent.withValues(alpha: 0.12),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(9),
            child: Icon(icon, size: 20, color: AppColors.accent),
          ),
        ),
      ),
    );
  }
}

/// Map-style selector chip (Map / Satellite / Hybrid).
class _MapTypeChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _MapTypeChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.accent : AppColors.textSecondary;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: selected ? 0.14 : 0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 17, color: color),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom action chip (Traffic / Fit route / My location).
class _ToggleChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  const _ToggleChip({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.accent : AppColors.textSecondary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: active ? 0.14 : 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}