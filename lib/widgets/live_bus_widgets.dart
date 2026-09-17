import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gm;
import 'package:latlong2/latlong.dart';
import '../core/l10n/l10n.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/formatters.dart';
import '../models/shuttle.dart';
import '../services/live_tracking_service.dart';
import '../services/passenger_location_service.dart';
import 'google_map_kit.dart';
import 'fullscreen_map_screen.dart';
import 'user_location_marker.dart';

/// Compact live-status strip used on the home "boarding next" card. Polls a
/// timer every ~5s to refresh the displayed bus position along the route and
/// shows the distance to the passenger's stop plus the ETA countdown. Tapping
/// opens the full-screen live tracking map.
class LiveBusStrip extends StatefulWidget {
  final Ticket ticket;
  const LiveBusStrip({super.key, required this.ticket});

  @override
  State<LiveBusStrip> createState() => _LiveBusStripState();
}

class _LiveBusStripState extends State<LiveBusStrip> {
  Timer? _timer;
  late final LiveTripTracker _tracker;
  late final ShuttleStop? _stop;

  @override
  void initState() {
    super.initState();
    _tracker = LiveTripTracker.fromTicket(widget.ticket);
    _stop = pickupStopFor(widget.ticket);
    if (_tracker.path.isNotEmpty) {
      _timer = Timer.periodic(const Duration(seconds: 5), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_tracker.path.isEmpty) return const SizedBox.shrink();
    final now = DateTime.now();
    final liveGps = widget.ticket.driver?.livePosition(now);
    final position = liveGps ?? _tracker.positionAt(now);
    if (position == null) return const SizedBox.shrink();
    final km =
        liveGps == null
            ? _tracker.kmToPickup(now, _stop)
            : _tracker.path.kmFromPositionToStop(liveGps, _stop);
    final eta = _tracker.eta(now);
    final fraction = _tracker.fractionAt(now);
    final departed = _tracker.hasDeparted(now);

    return GestureDetector(
      onTap:
          () => Navigator.of(
            context,
          ).pushNamed('/live-tracking', arguments: widget.ticket),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        decoration: BoxDecoration(
          color: AppColors.accent.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.accent.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const _PulseDot(),
                const SizedBox(width: 6),
                Text(
                  departed
                      ? L10n.t(context, 'onTheMove')
                      : '${L10n.t(context, 'arrivingIn')} ${_countdown(context, eta)}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppColors.accent,
                  ),
                ),
                const Spacer(),
                if (km != null)
                  Text(
                    L10n.t(
                      context,
                      'kmToStop',
                    ).replaceFirst('{km}', Formatters.distanceKm(km)),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textSecondary,
                    ),
                  ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: AppColors.textTertiary,
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: fraction.clamp(0.0, 1.0),
                minHeight: 5,
                color: AppColors.accent,
                backgroundColor: AppColors.accent.withValues(alpha: 0.15),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _countdown(BuildContext context, Duration d) {
    final min = d.inMinutes;
    final h = min ~/ 60;
    final m = min % 60;
    if (min < 1) return L10n.t(context, 'nowShort');
    if (h > 0) {
      return '$h${L10n.t(context, 'hoursShort')} '
          '$m${L10n.t(context, 'minutesShort')}';
    }
    return '$m${L10n.t(context, 'minutesShort')}';
  }
}

/// Full live-tracking card used on the ticket screen: a mini map with the
/// route polyline + moving bus marker, ETA, remaining stops and distance to
/// the passenger's pickup. Tapping opens the full-screen live tracking map.
class LiveBusCard extends StatefulWidget {
  final Ticket ticket;
  const LiveBusCard({super.key, required this.ticket});

  @override
  State<LiveBusCard> createState() => _LiveBusCardState();
}

class _LiveBusCardState extends State<LiveBusCard> {
  Timer? _timer;
  late final LiveTripTracker _tracker;
  late final ShuttleStop? _stop;
  gm.GoogleMapController? _controller;
  bool _locating = false;

  gm.BitmapDescriptor? _originIcon;
  gm.BitmapDescriptor? _wayIcon;
  gm.BitmapDescriptor? _destIcon;
  gm.BitmapDescriptor? _userIcon;
  gm.BitmapDescriptor? _busDotIcon;
  Set<gm.Polyline> _polylines = {};

  @override
  void initState() {
    super.initState();
    _tracker = LiveTripTracker.fromTicket(widget.ticket);
    _stop = pickupStopFor(widget.ticket);
    if (_tracker.path.isNotEmpty) {
      _timer = Timer.periodic(const Duration(seconds: 5), (_) {
        if (mounted) setState(() {});
      });
    }
    final location = PassengerLocationService.instance;
    location.addListener(_onLocationChanged);
    unawaited(location.start());
    unawaited(_loadIcons());
  }

  Future<void> _loadIcons() async {
    final stripColor = widget.ticket.vehicleClass?.color ?? AppColors.accent;
    final results = await Future.wait(<Future<Object>>[
      originDot(stripColor),
      waypointDot(AppColors.textTertiary),
      destinationPin(stripColor),
      userDot(const Color(0xFF1E88E5)),
      _busIcon(stripColor),
    ]);
    if (!mounted) return;
    setState(() {
      _originIcon = results[0] as gm.BitmapDescriptor;
      _wayIcon = results[1] as gm.BitmapDescriptor;
      _destIcon = results[2] as gm.BitmapDescriptor;
      _userIcon = results[3] as gm.BitmapDescriptor;
      _busDotIcon = results[4] as gm.BitmapDescriptor;
    });
    final pts = _tracker.path.points;
    if (pts.length < 2) return;
    final polylines = await routePolylines(
      id: 'card-route',
      points: pts,
      color: stripColor,
      width: 3,
    );
    if (!mounted) return;
    setState(() => _polylines = {...polylines});
  }

  void _onLocationChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _timer?.cancel();
    final location = PassengerLocationService.instance;
    location.removeListener(_onLocationChanged);
    location.stop();
    _controller?.dispose();
    super.dispose();
  }

  /// Recenters the mini map on the passenger's current device position.
  Future<void> _locateMe() async {
    final location = PassengerLocationService.instance;
    setState(() => _locating = true);
    try {
      final pos = await location.getSingleFix();
      if (!mounted) return;
      if (pos == null) {
        _snack(L10n.t(context, 'locationUnavailable'));
        return;
      }
      await _controller?.moveCamera(
        gm.CameraUpdate.newCameraPosition(
          gm.CameraPosition(target: toGm(pos), zoom: 15),
        ),
      );
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Set<gm.Marker> _markersFor(List<LatLng> pts, LatLng busPos) {
    final markers = <gm.Marker>{};
    for (var i = 0; i < pts.length; i++) {
      final icon = i == 0
          ? _originIcon
          : i == pts.length - 1
          ? _destIcon
          : _wayIcon;
      if (icon == null) continue;
      markers.add(
        gm.Marker(
          markerId: gm.MarkerId('stop-$i'),
          position: toGm(pts[i]),
          icon: icon,
          anchor: Offset(0.5, i == pts.length - 1 ? 0.95 : 0.5),
          zIndexInt: 2,
        ),
      );
    }
    final busIcon = _busDotIcon;
    if (busIcon != null) {
      markers.add(
        gm.Marker(
          markerId: const gm.MarkerId('bus'),
          position: toGm(busPos),
          icon: busIcon,
          anchor: const Offset(0.5, 0.5),
          zIndexInt: 20,
        ),
      );
    }
    final userIcon = _userIcon;
    final userPos = PassengerLocationService.instance.currentPosition;
    if (userPos != null && userIcon != null) {
      markers.add(
        gm.Marker(
          markerId: const gm.MarkerId('me'),
          position: toGm(userPos),
          icon: userIcon,
          anchor: const Offset(0.5, 0.5),
          zIndexInt: 30,
        ),
      );
    }
    return markers;
  }

  @override
  Widget build(BuildContext context) {
    if (_tracker.path.isEmpty) return const SizedBox.shrink();
    final now = DateTime.now();
    final liveGps = widget.ticket.driver?.livePosition(now);
    final position = liveGps ?? _tracker.positionAt(now);
    if (position == null) return const SizedBox.shrink();
    final km =
        liveGps == null
            ? _tracker.kmToPickup(now, _stop)
            : _tracker.path.kmFromPositionToStop(liveGps, _stop);
    final eta = _tracker.eta(now);
    final remaining =
        liveGps == null
            ? _tracker.remainingStops(now)
            : _tracker.remainingStopsFromPosition(liveGps);
    final pts = _tracker.path.points;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: SizedBox(
            height: 170,
            child: Stack(
              children: [
                Positioned.fill(
                  child: gm.GoogleMap(
                    initialCameraPosition: gm.CameraPosition(
                      target: toGm(pts.first),
                      zoom: 12,
                    ),
                    onMapCreated: (c) {
                      _controller = c;
                      c.moveCamera(cameraForBounds(pts, padding: 30));
                    },
                    markers: _markersFor(pts, position),
                    polylines: _polylines,
                    style: googleMapStyle(),
                    zoomControlsEnabled: false,
                    compassEnabled: false,
                    mapToolbarEnabled: false,
                    myLocationButtonEnabled: false,
                    myLocationEnabled: false,
                    rotateGesturesEnabled: true,
                    tiltGesturesEnabled: true,
                  ),
                ),
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: LocateMeButton(
                    busy: _locating,
                    tooltip: L10n.t(context, 'locateMe'),
                    onTap: _locateMe,
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: MapExpandButton(
                    points: pts,
                    originLabel: widget.ticket.from,
                    destinationLabel: widget.ticket.to,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            const _PulseDot(),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '${L10n.t(context, 'arrivingIn')} '
                '${_countdown(context, eta)}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppColors.accent,
                ),
              ),
            ),
            Text(
              '$remaining ${L10n.t(context, 'remainingStops')}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        if (km != null) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(
                Icons.near_me_rounded,
                size: 15,
                color: AppColors.textTertiary,
              ),
              const SizedBox(width: 6),
              Text(
                L10n.t(
                  context,
                  'kmToStop',
                ).replaceFirst('{km}', Formatters.distanceKm(km)),
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
              const Spacer(),
              Text(
                L10n.t(
                  context,
                  liveGps == null
                      ? 'estimatedPositionNote'
                      : 'liveGpsPositionNote',
                ),
                style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.textTertiary,
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed:
                () => Navigator.of(
                  context,
                ).pushNamed('/live-tracking', arguments: widget.ticket),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.accent,
              side: BorderSide(color: AppColors.accent.withValues(alpha: 0.4)),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: const Icon(Icons.map_outlined, size: 18),
            label: Text(
              L10n.t(context, 'trackLive'),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ],
    );
  }

  static String _countdown(BuildContext context, Duration d) {
    final min = d.inMinutes;
    final h = min ~/ 60;
    final m = min % 60;
    if (min < 1) return L10n.t(context, 'nowShort');
    if (h > 0) {
      return '$h${L10n.t(context, 'hoursShort')} '
          '$m${L10n.t(context, 'minutesShort')}';
    }
    return '$m${L10n.t(context, 'minutesShort')}';
  }
}

/// Painted "shuttle on the road" badge: a compact rounded-square marker with
/// the bus glyph, drawn once and reused by Google Maps. ~42 px on screen and
/// visually distinct from the round stop dots.
Future<gm.BitmapDescriptor> _busIcon(Color color) => paintIcon(
      key: 'bus-${color.toARGB32()}',
      px: 42,
      painter: (c, s) {
        final body = RRect.fromRectAndRadius(
          Rect.fromLTWH(s * 0.12, s * 0.12, s * 0.76, s * 0.76),
          Radius.circular(s * 0.22),
        );
        c.drawRRect(
          RRect.fromRectAndRadius(
            body.outerRect.inflate(s * 0.1),
            Radius.circular(s * 0.28),
          ),
          Paint()..color = Colors.black.withValues(alpha: 0.08),
        );
        c.drawRRect(body, Paint()..color = color);
        c.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(s * 0.2, s * 0.2, s * 0.6, s * 0.6),
            Radius.circular(s * 0.18),
          ),
          Paint()..color = Colors.white.withValues(alpha: 0.28),
        );
        final icon = Icons.airport_shuttle_rounded;
        final tp = TextPainter(
          textDirection: TextDirection.ltr,
          text: TextSpan(
            text: String.fromCharCode(icon.codePoint),
            style: TextStyle(
              fontSize: s * 0.46,
              fontFamily: icon.fontFamily,
              package: icon.fontPackage,
              height: 1,
            ),
          ),
        )..layout();
        tp.paint(
          c,
          Offset((s - tp.width) / 2, (s - tp.height) / 2),
        );
      },
    );

/// The animated "live" dot used by both widgets.
class _PulseDot extends StatelessWidget {
  const _PulseDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: AppColors.accent,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: AppColors.accent.withValues(alpha: 0.5),
            blurRadius: 4,
          ),
        ],
      ),
    );
  }
}
